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

struct GBPeerError: Error {
    let message: String

    init(message: String) {
        self.message = message
    }
}

struct UnknownError: Error {
}

protocol GBPeerDelegate: AnyObject {
    func peerJs(_ sender: GBPeer, onOpen withId: String?)
    func peerJs(_ sender: GBPeer, onClose: ())
    func peerJs(_ sender: GBPeer, onError: Error)
    func peerJs(_ sender: GBPeer, onDisconnected withId: String?)
}

public class GBPeer: NSObject {
    private let options: PeerOptions

    internal var socket: ISocket?
    private var connections: [String: [IConnection]] = [:]

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

        let randomTokenSeed = "abcdefghijklmnopqrstuvwxyz0123456789"
        randomToken = String((0..<11).compactMap({ _ in randomTokenSeed.randomElement() }))
        super.init()

        socket = createServerConnection()
        socket?.delegate = self

        logger.debug = options.debug

        initialize(userId)
    }

    private func emitError(_ message: String) {
        delegate?.peerJs(self, onError: GBPeerError(message: message))
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
        logger.error("Aborting!");

        if let error {
            emitError(error)
        } else {
            emitError("Aborted!")
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
    func handleMessage(_ message: Socket.StringMessageResponse) {
        let type = message.decodedResponse["type"] as? String

        switch type {
        case "OPEN": // The connection to the server is open.
            lastServerId = id
            open = true
            delegate?.peerJs(self, onOpen: id)
        case "ERROR": // Server error.
            var error = "Error"
            if let payloadError = message.decodedPayload["type"] as? String {
                error = payloadError ?? error
            }
            abort(GBPeerError(message: error))
        case "ID-TAKEN": // The selected ID is taken.
            abort(GBPeerError(message: "ID \(id ?? "-") is taken"))
        case "INVALID-KEY": // The given API key cannot be found.
            abort(GBPeerError(message: "API KEY \(options.key ?? "-") is invalid"))
        case "LEAVE": // Another peer has closed its connection to this peer.
            let peerId = message.decodedResponse["src"] as? String
            if let peerId = peerId {
                logger.log("Received leave message from \(peerId ?? "-")")
                cleanupPeer(peerId)
                connections.removeValue(forKey: peerId)
            }
        case "EXPIRE": // The offer sent to a peer has expired without response.
            let peerId = message.decodedResponse["src"] as? String
            emitError("Could not connect to peer \(peerId ?? "-")")
        case "OFFER":
            break
                // // we should consider switching this to CALL/CONNECT, but this is the least breaking option.
                // const connectionId = payload.connectionId
                // let connection = this.getConnection(peerId, connectionId)
                //
                // if (connection) {
                //     connection.close()
                //     logger.warn(
                //             `Offer received for existing Connection ID:$ {
                //         connectionId
                //     }`,
                //     )
                // }
                //
                // // Create a new connection.
                // if (payload.type === ConnectionType.Media) {
                //     const mediaConnection = new MediaConnection(peerId, this, {
                //         connectionId: connectionId,
                //         _payload: payload,
                //         metadata: payload.metadata,
                //     })
                //     connection = mediaConnection
                //     this._addConnection(peerId, connection)
                //     this.emit("call", mediaConnection)
                // } else if (payload.type === ConnectionType.Data) {
                //     const dataConnection = new DataConnection(peerId, this, {
                //         connectionId: connectionId,
                //         _payload: payload,
                //         metadata: payload.metadata,
                //         label: payload.label,
                //         serialization: payload.serialization,
                //         reliable: payload.reliable,
                //     })
                //     connection = dataConnection
                //     this._addConnection(peerId, connection)
                //     this.emit("connection", dataConnection)
                // } else {
                //     logger.warn(`Received malformed connection type:$ {
                //         payload.type
                //     }`)
                //     return
                // }
                //
                // // Find messages.
                // const messages = this._getMessages(connectionId)
                // for (let message of messages) {
                //     connection.handleMessage(message)
                // }
                //
                // break
        default:
            let peerId = message.decodedResponse["src"] as? String
            if message.decodedPayload["type"] == nil {
                logger.log("You received a malformed message from \(peerId ?? "-") of type \(type ?? "-")")
            }
            if type == "ANSWER" {
                guard let payload = message.decodedResponse["payload"] as? [String: Any],
                      let sdp = payload["sdp"] as? [String: Any],
                      let sdpString = sdp["sdp"] as? String,
                      let sdpType = sdp["type"] as? String else {
                    fatalError("ANSWER call should have payload and sdp")
                }
                let remoteSdp = RTCSessionDescription(type: sdpType == "answer" ? .answer : .prAnswer, sdp: sdpString)

                logger.log("Setting remote description \(sdpString)")

                let setRemoteDescriptionRx: Completable = Completable.create { observer in
                    self.rtcPeer?.setRemoteDescription(remoteSdp, completionHandler: { (error) in
                        if let error = error {
                            observer(.error(error))
                        } else {
                            observer(.completed)
                        }
                    })
                    return Disposables.create()
                }
                do {
                    // try setRemoteDescriptionRx.andThen(Single.just(true)).toBlocking().first()
                } catch {
                    fatalError("Error Set remote description \(error)")
                }

                logger.log("Set remoteDescription:\(type ?? "-") for:\(remotePeerId ?? "-")")

                // sendOfferAlready = true
                // let pending = Array(pendingCandidates)
                // pendingCandidates.removeAll()
                // for p in pending {
                //     sendOffer(p)
                // }
            } else if type == "CANDIDATE" {
                if rtcPeer?.remoteDescription == nil {
                    fatalError("Remote description must be set")
                }
                guard let payload = message.decodedResponse["payload"] as? [String: Any],
                      let candidate = payload["candidate"] as? [String: Any],
                      let candidateString = candidate["candidate"] as? String else {
                    fatalError("CANDIDATE call should have payload and candidate")
                }
                logger.log("handleCandidate: \(candidateString)")

                let sdpMLineIndex = candidate["sdpMLineIndex"] as? Int
                let sdpMLineIndex32: Int32
                if let sdpMLineIndex {
                    sdpMLineIndex32 = Int32(sdpMLineIndex)
                } else {
                    sdpMLineIndex32 = 0
                }
                let sdpMid = candidate["sdpMid"] as? String
                let provider = self

                let ice = RTCIceCandidate(sdp: candidateString, sdpMLineIndex: sdpMLineIndex32, sdpMid: sdpMid)

                let setIceCandidateRx: Completable = Completable.create { observer in
                    self.rtcPeer?.add(ice, completionHandler: { (error) in
                        if let error = error {
                            observer(.error(error))
                        } else {
                            observer(.completed)
                        }
                    })
                    return Disposables.create()
                }
                do {
                    // try setIceCandidateRx.andThen(Single.just(true)).toBlocking().first()
                } catch {
                    fatalError("Error Set ice candidate \(error)")
                }
                logger.log("Added ICE candidate for:\(remotePeerId ?? "-")")
            }

                // const connectionId = payload.connectionId
                // const connection = this.getConnection(peerId, connectionId)
                //
                // if (connection && connection.peerConnection) {
                //     // Pass it on.
                //     connection.handleMessage(message)
                // } else if (connectionId) {
                //     // Store for possible later use
                //     this._storeMessage(connectionId, message)
                // } else {
                //     logger.warn("You received an unrecognized message:", message)
                // }
                // break
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

    func socketJs(onNewMessage data: Socket.StringMessageResponse) {
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
