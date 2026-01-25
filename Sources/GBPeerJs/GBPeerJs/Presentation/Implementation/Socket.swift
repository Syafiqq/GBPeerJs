//
// Created by engineering on 22/6/23.
//

import Foundation
import Starscream

private let kVersion = "1.4.7"

class Socket: ISocket {
    private let secure: Bool
    private let host: String
    private let port: Int
    private let path: String
    private let key: String
    private let pingInterval: TimeInterval

    private var id: String?
    private let baseUrl: String
    private var disconnected = true

    private var socket: WebSocket?
    private var messagesQueue: [String] = []
    private var messagesQueueQueue = DispatchQueue(label: "Socket_messagesQueue", attributes: .concurrent)

    private var heartbeatWorkItem: DispatchWorkItem?

    weak var delegate: SocketDelegate?

    private let logger: ILogger = Logger.shared

    init(
            secure: Bool,
            host: String,
            port: Int,
            path: String,
            key: String,
            pingInterval: TimeInterval
    ) {
        self.secure = secure
        self.host = host
        self.port = port
        self.path = path
        self.key = key
        self.pingInterval = pingInterval

        let wsProtocol = secure ? "wss://" : "ws://"
        baseUrl = "\(wsProtocol)\(host):\(port)\(path)peerjs?key=\(key)"
    }

    func start(id: String, token: String) {
        doStart(id: id, token: token)
    }

    func close() {
        doClose()
    }

    func send(_ message: String) {
        doSend(message)
    }
}

private extension Socket {
    func doStart(id: String, token: String) {
        self.id = id

        let wsUrl = "\(baseUrl)&id=\(id)&token=\(token)"

        if socket != nil || !disconnected {
            return
        }

        guard let url = URL(string: "\(wsUrl)&version=\(kVersion)") else {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let socket = WebSocket(
            request: request,
            certPinner: FoundationSecurity(),
            compressionHandler: nil,
            useCustomEngine: false
        )
        disconnected = false
        socket.delegate = self

        self.socket = socket
        socket.connect()
    }

    func scheduleHeartbeat() {
        let heartbeatWorkItem = DispatchWorkItem { [weak self] in
            self?.sendHeartbeat()
        }
        self.heartbeatWorkItem = heartbeatWorkItem

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(pingInterval)), execute: heartbeatWorkItem)
    }

    func sendHeartbeat() {
        guard wsOpen() else {
            logger.log("Cannot send heartbeat, because socket closed")
            return
        }

        socket?.write(string: "{\"type\":\"\(ServerMessageType.heartbeat)\"}")
        scheduleHeartbeat()
    }

    func wsOpen() -> Bool {
        socket != nil && !disconnected
    }

    func sendQueuedMessages() {
        // Create copy of queue and clear it,
        // because send method push the message back to queue if smth will go wrong
        let copiedQueue = messagesQueueQueue.sync {
            Array(messagesQueue)
        }
        messagesQueueQueue.async { [weak self] in
            self?.messagesQueue.removeAll()
        }

        for message in copiedQueue {
            doSend(message)
        }
    }

    func doSend(_ message: String) {
        if disconnected {
            return
        }

        // If we didn't get an ID yet, we can't yet send anything so we should queue
        // up these messages.
        if id == nil {
            messagesQueueQueue.async { [weak self] in
                self?.messagesQueue.append(message)
            }
            return
        }

        // if (!data.type) {
        //     this.emit(SocketEventType.Error, "Invalid message");
        //     return;
        // }

        if !wsOpen() {
            return
        }

        socket?.write(string: message)
    }

    func doClose() {
        if disconnected {
            return
        }

        cleanup()

        disconnected = true
    }

    func cleanup() {
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
        heartbeatWorkItem?.cancel()
    }
}

extension Socket: WebSocketDelegate {
    // Take care of the queue of connections if necessary and make sure Peer knows
    // socket is open.
    func websocketDidConnect(socket: Starscream.WebSocketClient) {
        if disconnected {
            return
        }
        disconnected = false

        sendQueuedMessages()

        logger.log("Socket open")

        scheduleHeartbeat()
    }

    func websocketDidDisconnect(socket: Starscream.WebSocketClient, error: Error?) {
        heartbeatWorkItem?.cancel()

        if disconnected {
            return
        }

        if let error {
            logger.log("Socket closed.", error)
        } else {
            logger.log("Socket closed.")
        }

        cleanup()
        disconnected = true

        delegate?.socketJs(onDisconnected: ())
    }

    func websocketDidReceiveMessage(socket: Starscream.WebSocketClient, text: String) {
        logger.log("Server message:string received:", text)

        let data: [String: Any]
        if let source = text.data(using: .utf8) {
            do {
                data = (try JSONSerialization.jsonObject(with: source, options: []) as? [String: Any]) ?? [:]
            } catch {
                logger.error("Decode Error", error)
                data = [:]
            }
        } else {
            data = [:]
        }
        delegate?.socketJs(onNewMessage: data)
    }

    func websocketDidReceiveData(socket: Starscream.WebSocketClient, data: Data) {
        logger.log("Server message:data received:", data.count)

        delegate?.socketJs(onNewMessage: data)
    }

    // swiftlint:disable:next cyclomatic_complexity
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(let headers):
            websocketDidConnect(socket: client)
        case .disconnected:
            websocketDidDisconnect(socket: client, error: nil)
        case .text(let string):
            websocketDidReceiveMessage(socket: client, text: string)
        case .binary(let data):
            websocketDidReceiveData(socket: client, data: data)
        case .ping:
            break
        case .pong:
            break
        case .viabilityChanged:
            break
        case .reconnectSuggested:
            break
        case .cancelled:
            break
        case .error(let error):
            websocketDidDisconnect(socket: client, error: error)
        case .peerClosed:
           break
        }
    }
}
