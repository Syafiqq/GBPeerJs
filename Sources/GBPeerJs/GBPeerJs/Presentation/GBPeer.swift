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

    private var socket: ISocket?
    private var connections: [String: String] = [:]

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

        // socket = createServerConnection()
        // socket?.delegate = self

        logger.debug = options.debug

        // initialize(userId)
    }

    private func emitError(_ message: String) {
        delegate?.peerJs(self, onError: GBPeerError(message: message))
    }

    private func emitError(_ error: Error) {
        delegate?.peerJs(self, onError: error)
    }

    func cleanup() {
        // destroyServerConnection()
        if let id = id {
            // cleanupPeer(id)
        }
    }

    func requestReconnect() {
        // reconnect()
    }
}

extension GBPeer: IPeer {
    func getConnection(peerId: String, connectionId: String) -> IConnection {
        fatalError("getConnection(peerId:connectionId:) has not been implemented")
    }

    func getMessage(connectionId: String) -> [[String: Any]] {
        fatalError("getMessage(connectionId:) has not been implemented")
    }

    func removeConnection(_ connection: IConnection) {
    }
}

// MARK: - Config
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

        init(debug: Bool,
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

        init(iceServers: [RTCIceServer], sdpSemantics: RTCSdpSemantics, customConfig: ((RTCPeerConnection) -> ())?) {
            self.iceServers = iceServers
            self.sdpSemantics = sdpSemantics
            self.customConfig = customConfig
        }
    }
}

struct GBPeerError: Error {
    let message: String

    init(message: String) {
        self.message = message
    }
}
