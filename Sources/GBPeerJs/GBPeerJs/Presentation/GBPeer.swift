//
// Created by engineering on 27/6/23.
//

import Foundation
import WebRTC
import RxSwift

private let kKeyDefault = "peerjs"
private let kHostDefault = "0.peerjs.com"
private let kPortDefault = 443
private let kPingIntervalDefault = TimeInterval(5000)
private let kPathDefault = "/"

// MARK: - Config

struct UnknownError: Error {
}

protocol GBPeerDelegate: AnyObject {
    func peerJs(_ sender: GBPeer, onOpen withId: String?)
    func peerJs(_ sender: GBPeer, onClose: ())
    func peerJs(_ sender: GBPeer, onError: Error)
    func peerJs(_ sender: GBPeer, onDisconnected withId: String?)
    func peerJs(_ sender: GBPeer, onCall withConnection: IConnection)
}

public class GBPeer: NSObject {
    private let options: PeerOptions

    internal var socket: ISocket?
    private var connections: [String: [IConnection]] = [:]
    private var lostMessages: [String: [[String: Any]]] = [:]

    private var id: String?
    private var lastServerId: String?
    private let randomToken: String

    private var destroyed = false
    private var disconnected = false
    private var open = false

    weak var delegate: GBPeerDelegate?

    private var rtcPeer: RTCPeerConnection?
    private var rtcPeerFactory: RTCPeerConnectionFactory?

    private var remotePeerId: String?
    private var connectionId: String?

    private var logger: ILogger = Logger()

    init(
            id: String,
            options: PeerOptions
    ) {
        let userId = id
        self.options = options

        randomToken = Util.randomToken(11)
        super.init()

        socket = createServerConnection()
        socket?.delegate = self

        logger.debug = options.debug

        initialize(userId)
    }

    private func emitError(_ message: String) {
        delegate?.peerJs(self, onError: GBPeerJsError.peerError(reason: .unknownError(message)))
    }

    private func emitError(_ error: Error) {
        delegate?.peerJs(self, onError: error)
    }

    /** Disconnects every connection on this peer. */
    func cleanup() {
        for peerId in connections.keys {
            cleanupPeer(peerId)
            connections[peerId]?.removeAll()
        }
        connections.removeAll()

        destroyServerConnection()
    }

    func reconnect() throws {
        try doReconnect()
    }
}

extension GBPeer: IPeer {
    /** Retrieve a data/media connection for this peer. */
    func getConnection(peerId: String, connectionId: String) -> IConnection? {
        let connections = connections[peerId]
        if connections?.isEmpty == true {
            return nil
        }

        return connections?.first(where: { $0.connectionId == connectionId })
    }

    func getMessage(connectionId: String) -> [[String: Any]] {
        fatalError("getMessage(connectionId:) has not been implemented")
    }

    func removeConnection(_ connection: IConnection) {
        var connections = connections[connection.peer]

        if connections?.isEmpty == false {
            if let index = connections?.firstIndex(where: { $0 === connection }) {
                connections?.remove(at: index)
            }

            self.connections[connection.peer] = connections
        }

        // remove from lost messages
        lostMessages.removeValue(forKey: connection.peer)
    }

    /** Add a data/media connection to this peer. */
    func addConnection(peerId: String, connection: IConnection) {
        logger.log("add connection \(connection.type):\(connection.connectionId) to peerId:\(peerId)")

        if connections.keys.contains(peerId) {
            connections[peerId] = []
        } else {
            var peerConnections = connections[peerId] ?? []
            peerConnections.append(connection)
            connections[peerId] = peerConnections
        }
    }

    /**
     * Calls the remote peer specified by id and returns a media connection.
     * @param peer The brokering ID of the remote peer (their peer.id).
     * @param stream The caller's media stream
     * @param options Metadata associated with the connection, passed in by whoever initiated the connection.
     */
    func call(
            peerId peer: String,
            stream: RTCMediaStream?
    ) throws -> MediaConnection {
        if disconnected {
            logger.warn(
                    "You cannot connect to a new Peer because you called " +
                            ".disconnect() on this Peer and ended your connection with the " +
                            "server. You can create a new Peer to reconnect."
            )
            throw GBPeerJsError.peerError(reason: .connectPeerOnDisconnectServer)
        }

        guard let stream = stream else {
            logger.error("To call a peer, you must provide a stream from your browser's `getUserMedia`.")
            throw GBPeerJsError.peerError(reason: .connectPeerWithoutMedia)
        }

        let mediaConnection = MediaConnection(
                peer: peer,
                provider: self,
                connectionId: nil,
                stream: stream,
                logger: logger,
                remoteOfferPayload: [:]
        )
        addConnection(peerId: peer, connection: mediaConnection)
        return mediaConnection
    }

    // TODO Change it to private
    /** Retrieve messages from lost message store */
    func getMessages(connectionId: String) -> [[String: Any]] {
        let messages = lostMessages[connectionId] ?? []

        if !messages.isEmpty {
            lostMessages.removeValue(forKey: connectionId)
            return messages
        }

        return []
    }

    func storeMessage(connectionId: String, message: [String: Any]) {
        if lostMessages.keys.contains(connectionId) {
            lostMessages[connectionId] = []
        } else {
            var peerConnections = lostMessages[connectionId] ?? []
            peerConnections.append(message)
            lostMessages[connectionId] = peerConnections
        }
    }
}

extension GBPeer: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("WebRTC - didChange stateChanged - \(stateChanged) | Called when the SignalingState changed.")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("WebRTC - didAdd stream | Called when media is received on a new stream from remote peer.")

        logger.log("Received remote stream")

        logger.log("add stream \(stream.streamId) to media connection \(connectionId ?? "-")")

        if let track = stream.audioTracks.first {
            track.isEnabled = true
            track.source.volume = 10
            // self.stream = stream
            // self.track = track
            // reconfigureAudio()
        } else {
            logger.log("Weird looking stream")
        }

        logger.log("Receiving stream")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("WebRTC - didRemove stream | Called when a remote peer closes a stream.")
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("""
              WebRTC - peerConnectionShouldNegotiate | Called when negotiation is needed,
              for example ICE has restarted.
              """)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("WebRTC - didChange newState \(newState) | Called any time the IceConnectionState changes.")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("WebRTC - didChange newState \(newState) | Called any time the IceGatheringState changes")
        // iceGatheringStateRelay.accept(newState)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("WebRTC - didGenerate candidate | New ice candidate has been found.")

        let peerId = remotePeerId ?? ""
        let connectionId = connectionId ?? ""
        let connectionType = "media"

        guard !candidate.sdp.isEmpty else {
            return
        }

        logger.log("Received ICE candidates for \(peerId):\(candidate.sdp)")

        // if sendOfferAlready {
        //     sendOffer(candidate)
        // } else {
        //     pendingCandidates.append(candidate)
        // }
    }

    private func sendOffer(_ candidate: RTCIceCandidate) {
        let peerId = remotePeerId ?? ""
        let connectionId = connectionId ?? ""
        let connectionType = "media"

        let candidateEntity = LocalCandidateRequestEntity(
                type: "CANDIDATE",
                payload: .init(
                        candidate: .init(
                                candidate: candidate.sdp,
                                sdpMLineIndex: candidate.sdpMLineIndex,
                                sdpMid: candidate.sdpMid
                        ),
                        type: "media",
                        connectionId: connectionId
                ),
                dst: peerId
        )
        let candidateEncoder = JSONEncoder()
        let candidateJson: String
        do {
            let candidateData = try candidateEncoder.encode(candidateEntity)
            candidateJson = String(data: candidateData, encoding: .utf8) ?? ""
        } catch {
            fatalError("Create Candidate json failed")
        }
        socket?.send(candidateJson)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("WebRTC - didRemove candidates | Called when a group of local Ice candidates have been removed.")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("WebRTC - didOpen dataChannel | New data channel has been opened.")
    }
}

// MARK: - Private

private extension GBPeer {
    func initialize(_ id: String) {
        self.id = id
        socket?.start(id: id, token: options.token ?? randomToken)
    }

    /** Closes all connections to this peer. */
    func cleanupPeer(_ peerId: String) {
        let connections = connections[peerId] ?? []

        guard !connections.isEmpty else {
            return
        }

        for connection in connections {
            connection.close()
        }
    }
}

// MARK: - Connectivity

private extension GBPeer {
    /**
     * Disconnects the Peer's connection to the PeerServer. Does not close any
     *  active connections.
     * Warning: The peer can no longer create or accept connections after being
     *  disconnected. It also cannot reconnect to the server.
     */
    func disconnect() {
        if disconnected {
            return
        }

        let currentId = id

        logger.log("Disconnect peer with ID:\(currentId ?? "-")")

        disconnected = true
        open = false

        socket?.close()

        lastServerId = currentId
        id = nil

        delegate?.peerJs(self, onDisconnected: currentId)
    }

    /**
     * Destroys the Peer: closes all active connections as well as the connection
     *  to the server.
     * Warning: The peer can no longer create or accept connections after being
     *  destroyed.
     */
    func destroy() {
        if destroyed {
            return
        }

        logger.log("Destroy peer with ID:\(id ?? "-")")

        disconnect()
        cleanup()

        destroyed = true

        delegate?.peerJs(self, onClose: ())
    }

    /** Attempts to reconnect with the same ID. */
    func doReconnect() throws {
        if disconnected && !destroyed {
            logger.log("Attempting reconnection to server with ID \(lastServerId ?? "-")")
            disconnected = false
            if let lastServerId {
                initialize(lastServerId)
            }
        } else if destroyed {
            logger.log("This peer cannot reconnect to the server. It has already been destroyed.")
            throw GBPeerJsError.peerError(reason: .disconnectAlready)
        } else if !disconnected && !open {
            // Do nothing. We're still connecting the first time.
            logger.log("In a hurry? We're still trying to make the initial connection!")
        } else {
            logger.log("Peer \(id ?? "-") cannot reconnect because it is not disconnected from the server!")
            throw GBPeerJsError.peerError(reason: .stillConnected)
        }
    }

    /**
     * Emits an error message and destroys the Peer.
     * The Peer is not destroyed if it's in a disconnected state, in which case
     * it retains its disconnected state and its existing connections.
     */
    func abort(_ error: Error?) {
        logger.error("Aborting!")

        if let error {
            emitError(error)
        } else {
            emitError(GBPeerJsError.peerError(reason: .peerAborted))
        }

        if lastServerId == nil {
            destroy()
        } else {
            disconnect()
        }
    }

    func delayedAbort(_ error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.abort(error)
        }
    }
}

// MARK: - Data

private extension GBPeer {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func handleMessage(_ message: [String: Any]) {
        let type = message["type"] as? String

        switch type {
        case ServerMessageType.open.rawValue: // The connection to the server is open.
            lastServerId = id
            open = true
            delegate?.peerJs(self, onOpen: id)
        case ServerMessageType.error.rawValue: // Server error.
            var error = "Error"
            if let payload = message["payload"] as? [String: Any],
               let payloadMessage = payload["msg"] as? String {
                error = payloadMessage
            }
            abort(GBPeerJsError.peerError(reason: .unknownError(error)))
        case ServerMessageType.idTaken.rawValue: // The selected ID is taken.
            abort(GBPeerJsError.peerError(reason: .unknownError("ID \(id ?? "-") is taken")))
        case ServerMessageType.invalidKey.rawValue: // The given API key cannot be found.
            abort(GBPeerJsError.peerError(reason: .unknownError("API KEY \(options.key ?? "-") is invalid")))
        case ServerMessageType.leave.rawValue: // Another peer has closed its connection to this peer.
            let peerId = message["src"] as? String
            logger.log("Received leave message from \(peerId ?? "-")")
            if let peerId {
                cleanupPeer(peerId)
                connections.removeValue(forKey: peerId)
            }
        case ServerMessageType.expire.rawValue: // The offer sent to a peer has expired without response.
            let peerId = (message["src"] as? String) ?? "-"
            emitError("Could not connect to peer \(peerId ?? "-")")
        case ServerMessageType.offer.rawValue:
            // we should consider switching this to CALL/CONNECT, but this is the least breaking option.
            if let peerId = message["src"] as? String,
               let payload = message["payload"] as? [String: Any],
               let connectionId = payload["connectionId"] as? String {

                if let connection = getConnection(peerId: peerId, connectionId: connectionId) {
                    connection.close()
                    logger.warn("Offer received for existing Connection ID:\(connectionId)")
                }

                let payloadType = payload["type"] as? String
                var connection: IConnection?
                // Create a new connection.
                if payloadType == ConnectionType.media.rawValue {
                    let mediaConnection = MediaConnection(
                            peer: peerId,
                            provider: self,
                            connectionId: connectionId,
                            stream: nil,
                            logger: logger,
                            remoteOfferPayload: payload
                    )
                    connection = mediaConnection
                    addConnection(peerId: peerId, connection: mediaConnection)
                    delegate?.peerJs(self, onCall: mediaConnection)
                }

                /*else if (payload.type === ConnectionType.Data) {
                    const dataConnection = new DataConnection(peerId, this, {
                        connectionId: connectionId,
                        _payload: payload,
                        metadata: payload.metadata,
                        label: payload.label,
                        serialization: payload.serialization,
                        reliable: payload.reliable,
                    });
                    connection = dataConnection;
                    this._addConnection(peerId, connection);
                    this.emit("connection", dataConnection);
                }*/

                else {
                    logger.warn("Received malformed connection type:\(payloadType ?? "-")")
                    return
                }

                let messages = getMessages(connectionId: connectionId)
                for message in messages {
                    connection?.handleMessage(message: message)
                }
            } else {
                logger.warn("Received malformed connection type:\(type ?? "-")")
            }
        default:
            break
        }
    }
}

// MARK: - Socket

private extension GBPeer {
    func createServerConnection() -> Socket {
        destroyServerConnection()
        let socket = Socket(
                secure: options.secure,
                host: options.host ?? kHostDefault,
                port: options.port ?? kPortDefault,
                path: options.path ?? kPathDefault,
                key: options.key ?? kKeyDefault,
                pingInterval: options.pingInterval ?? kPingIntervalDefault,
                logger: logger
        )
        socket.delegate = self

        return socket
    }

    func destroyServerConnection() {
        socket?.cleanup()
        socket?.delegate = nil
        socket = nil
    }
}

extension GBPeer: SocketDelegate {
    func socketJs(onDisconnected: ()) {
        if disconnected {
            return
        }

        emitError("Lost connection to server.")
        disconnect()
    }

    func socketJs(onNewMessage data: [String: Any]) {
        handleMessage(data)
    }

    func socketJs(onNewMessage: Data) {
        logger.log("onNewMessage(Data) not implemented yet")
    }

    func socketJs(onError error: Error?) {
        abort(error)
    }
}

extension GBPeer {
    struct PeerOptions {
        let debug: Bool
        let host: String?
        let port: Int?
        let path: String?
        let key: String?
        let token: String?
        let config: Config
        let secure: Bool
        let pingInterval: TimeInterval?

        init(
                debug: Bool,
                host: String? = nil,
                port: Int? = nil,
                path: String? = nil,
                key: String? = nil,
                token: String? = nil,
                config: Config,
                secure: Bool,
                pingInterval: TimeInterval? = nil
        ) {
            self.debug = debug
            self.host = host
            self.port = port
            self.path = path
            self.key = key
            self.token = token
            self.config = config
            self.secure = secure
            self.pingInterval = pingInterval
        }
    }

    struct Config {
        let iceServers: [RTCIceServer]
        let sdpSemantics: RTCSdpSemantics
        let customConfig: ((RTCPeerConnection) -> Void)?

        init(iceServers: [RTCIceServer], sdpSemantics: RTCSdpSemantics, customConfig: ((RTCPeerConnection) -> Void)?) {
            self.iceServers = iceServers
            self.sdpSemantics = sdpSemantics
            self.customConfig = customConfig
        }
    }
}
