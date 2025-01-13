//
// Created by engineering on 27/6/23.
//

import Foundation
import LiveKitWebRTC
import RxSwift

private let kKeyDefault = "peerjs"
private let kHostDefault = "0.peerjs.com"
private let kPortDefault = 443
private let kPingIntervalDefault = TimeInterval(5000)
private let kPathDefault = "/"

// MARK: - Config

public protocol GBPeerDelegate: AnyObject {
    func peerJs(_ sender: GBPeer, onOpen withId: String?)
    func peerJs(_ sender: GBPeer, onClose: ())
    func peerJs(_ sender: GBPeer, onDisconnected withId: String?)
    func peerJs(_ sender: GBPeer, onError: Error)
    func peerJs(_ sender: GBPeer, onCall withConnection: GBPeerConnection)
}

public class GBPeer {
    private let options: PeerOptions
    internal var socket: ISocket?

    private var id: String?
    private var lastServerId: String?
    private let randomToken: String

    private var destroyed = false
    private var disconnected = false
    private var open = false

    private var connections: [String: [IConnection]] = [:]
    private let connectionsQueue = DispatchQueue(label: "GBPeer_connections", attributes: .concurrent)
    private var lostMessages: [String: [[String: Any]]] = [:]
    private var lostMessagesQueue = DispatchQueue(label: "GBPeer_lostMessages", attributes: .concurrent)

    private var logger: ILogger = Logger.shared

    public weak var delegate: GBPeerDelegate?

    public init(
            id: String,
            options: PeerOptions
    ) {
        let userId = id
        self.options = options

        randomToken = Util.randomToken(11)

        socket = createServerConnection()
        socket?.delegate = self

        logger.debug = true

        initialize(userId)

        trackLifetime()
    }

    public func call(
            peerId peer: String,
            stream: GBPeerMediaStream
    ) throws -> GBPeerMediaConnection {
        try doCall(peerId: peer, stream: stream)
    }

    public func destroy() {
        doDestroy()
    }

    public func disconnect() {
        doDisconnect()
    }

    public func reconnect() throws {
        try doReconnect()
    }
}

private extension GBPeer {
    func createServerConnection() -> Socket {
        let socket = Socket(
                secure: options.secure,
                host: options.host ?? kHostDefault,
                port: options.port ?? kPortDefault,
                path: options.path ?? kPathDefault,
                key: options.key ?? kKeyDefault,
                pingInterval: options.pingInterval ?? kPingIntervalDefault
        )

        return socket
    }

    func initialize(_ id: String) {
        self.id = id
        socket?.start(id: id, token: options.token ?? randomToken)
    }

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
                connectionsQueue.async { [weak self] in
                    self?.connections.removeValue(forKey: peerId)
                }
            }
        case ServerMessageType.expire.rawValue: // The offer sent to a peer has expired without response.
            let peerId = (message["src"] as? String) ?? "-"
            emitError("Could not connect to peer \(peerId)")
        case ServerMessageType.offer.rawValue:
            // we should consider switching this to CALL/CONNECT, but this is the least breaking option.
            if let peerId = message["src"] as? String,
               let payload = message["payload"] as? [String: Any],
               let connectionId = payload["connectionId"] as? String {

                var connection: IConnection? = doGetConnection(peerId: peerId, connectionId: connectionId)
                if connection != nil {
                    connection?.requestClose()
                    logger.warn("Offer received for existing Connection ID:\(connectionId)")
                }

                let payloadType = payload["type"] as? String
                // Create a new connection.
                if payloadType == ConnectionType.media.rawValue {
                    let mediaConnection = GBPeerMediaConnection(
                            peer: peerId,
                            provider: self,
                            connectionId: connectionId,
                            stream: nil,
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

                let messages = doGetMessages(connectionId: connectionId)
                for message in messages {
                    connection?.handleMessage(message: message)
                }
            } else {
                logger.warn("Received malformed connection type:\(type ?? "-")")
            }
        default:
            let peerId = message["src"] as? String
            let payload = message["payload"] as? [String: Any]
            if payload == nil {
                logger.warn("You received a malformed message from \(peerId ?? "-") of type \(type ?? "-")")
                return
            }

            if let peerId,
               let payload {
                if let connectionId = payload["connectionId"] as? String,
                   let connection = doGetConnection(peerId: peerId, connectionId: connectionId),
                   connection.peerConnection != nil {
                    connection.handleMessage(message: message)
                } else if let connectionId = payload["connectionId"] as? String {
                    storeMessage(connectionId: connectionId, message: message)
                } else {
                    logger.warn("You received an unrecognized message:", message)
                }
            } else {
                logger.warn("Received malformed type:\(type ?? "-")")
            }
        }
    }

    func doStoreMessage(connectionId: String, message: [String: Any]) {
        if lostMessages.keys.contains(connectionId) {
            lostMessagesQueue.async { [weak self] in
                self?.lostMessages[connectionId] = [message]
            }
        } else {
            var peerConnections = lostMessagesQueue.sync {
                lostMessages[connectionId] ?? []
            }
            peerConnections.append(message)
            lostMessagesQueue.async { [weak self] in
                self?.lostMessages[connectionId] = peerConnections
            }
        }
    }

    // TODO Change it to private
    /** Retrieve messages from lost message store */
    func doGetMessages(connectionId: String) -> [[String: Any]] {
        let messages = lostMessagesQueue.sync {
            lostMessages[connectionId] ?? []
        }

        if !messages.isEmpty {
            lostMessagesQueue.async { [weak self] in
                self?.lostMessages.removeValue(forKey: connectionId)
            }
            return messages
        }

        return []
    }

    /**
     * Calls the remote peer specified by id and returns a media connection.
     * @param peer The brokering ID of the remote peer (their peer.id).
     * @param stream The caller's media stream
     * @param options Metadata associated with the connection, passed in by whoever initiated the connection.
     */
    func doCall(
            peerId peer: String,
            stream: GBPeerMediaStream
    ) throws -> GBPeerMediaConnection {
        if disconnected {
            logger.warn(
                    "You cannot connect to a new Peer because you called " +
                            ".disconnect() on this Peer and ended your connection with the " +
                            "server. You can create a new Peer to reconnect."
            )
            throw GBPeerJsError.peerError(reason: .connectPeerOnDisconnectServer)
        }

        /*guard let stream = stream else {
            logger.error("To call a peer, you must provide a stream from your browser's `getUserMedia`.")
            throw GBPeerJsError.peerError(reason: .connectPeerWithoutMedia)
        }*/

        let mediaConnection = GBPeerMediaConnection(
                peer: peer,
                provider: self,
                connectionId: nil,
                stream: stream,
                remoteOfferPayload: [:]
        )
        addConnection(peerId: peer, connection: mediaConnection)
        return mediaConnection
    }

    /** Add a data/media connection to this peer. */
    func addConnection(peerId: String, connection: IConnection) {
        logger.log("add connection \(connection.type):\(connection.connectionId) to peerId:\(peerId)")

        if !connections.keys.contains(peerId) {
            connectionsQueue.async { [weak self] in
                self?.connections[peerId] = [connection]
            }
        } else {
            var peerConnections = connectionsQueue.sync {
                connections[peerId] ?? []
            }
            peerConnections.append(connection)
            connectionsQueue.async { [weak self] in
                self?.connections[peerId] = peerConnections
            }
        }
    }

    func doRemoveConnection(_ connection: IConnection) {
        var connections = connectionsQueue.sync {
            self.connections[connection.peer]
        }

        if connections?.isEmpty == false {
            if let index = connections?.firstIndex(where: { $0 === connection }) {
                connections?.remove(at: index)
            }

            connectionsQueue.async { [weak self] in
                self?.connections[connection.peer] = connections
            }
        }

        // remove from lost messages
        lostMessagesQueue.async { [weak self] in
            self?.lostMessages.removeValue(forKey: connection.peer)
        }
    }

    /** Retrieve a data/media connection for this peer. */
    func doGetConnection(peerId: String, connectionId: String) -> IConnection? {
        let connections = connectionsQueue.sync {
            self.connections[peerId]
        }
        if connections?.isEmpty == true {
            return nil
        }

        return connections?.first(where: { $0.connectionId == connectionId })
    }

    func delayedAbort(_ error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.abort(error)
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
            doEmitError(error)
        } else {
            doEmitError(GBPeerJsError.peerError(reason: .peerAborted))
        }

        if lastServerId == nil {
            doDestroy()
        } else {
            doDisconnect()
        }
    }

    func emitError(_ message: String) {
        delegate?.peerJs(self, onError: GBPeerJsError.peerError(reason: .unknownError(message)))
    }

    func doEmitError(_ error: Error) {
        delegate?.peerJs(self, onError: error)
    }

    /**
     * Destroys the Peer: closes all active connections as well as the connection
     *  to the server.
     * Warning: The peer can no longer create or accept connections after being
     *  destroyed.
     */
    func doDestroy() {
        if destroyed {
            return
        }

        logger.log("Destroy peer with ID:\(id ?? "-")")

        doDisconnect()
        cleanup()

        destroyed = true

        delegate?.peerJs(self, onClose: ())
    }

    /** Disconnects every connection on this peer. */
    func cleanup() {
        for peerId in connections.keys {
            cleanupPeer(peerId)
            connectionsQueue.async {
                self.connections[peerId] = []
            }
        }
        connectionsQueue.async {
            self.connections.removeAll()
        }

        socket?.delegate = nil
        socket = nil
    }

    /** Closes all connections to this peer. */
    func cleanupPeer(_ peerId: String) {
        let connections = connectionsQueue.sync {
            self.connections[peerId] ?? []
        }

        guard !connections.isEmpty else {
            return
        }

        for connection in connections {
            connection.requestClose()
        }
    }

    /**
     * Disconnects the Peer's connection to the PeerServer. Does not close any
     *  active connections.
     * Warning: The peer can no longer create or accept connections after being
     *  disconnected. It also cannot reconnect to the server.
     */
    func doDisconnect() {
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
}

extension GBPeer: IPeer {
    func storeMessage(connectionId: String, message: [String: Any]) {
        doStoreMessage(connectionId: connectionId, message: message)
    }

    func getMessages(connectionId: String) -> [[String: Any]] {
        doGetMessages(connectionId: connectionId)
    }

    func removeConnection(_ connection: IConnection) {
        doRemoveConnection(connection)
    }

    func getConnection(peerId: String, connectionId: String) -> IConnection? {
        doGetConnection(peerId: peerId, connectionId: connectionId)
    }

    func emitError(_ error: Error) {
        doEmitError(error)
    }
}

extension GBPeer: SocketDelegate {
    func socketJs(onDisconnected: ()) {
        if disconnected {
            return
        }

        emitError("Lost connection to server.")
        doDisconnect()
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

import LifetimeTracker

extension GBPeer: LifetimeTrackable {
    public class var lifetimeConfiguration: LifetimeConfiguration {
        LifetimeConfiguration(maxCount: 1)
    }
}
