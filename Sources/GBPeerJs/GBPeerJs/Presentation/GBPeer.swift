//
// Created by engineering on 27/6/23.
//

import Foundation
import WebRTC
import RxSwift

public class GBPeer {
}

extension GBPeer: IPeer {
    var socket: ISocket? {
        fatalError("socket has not been implemented")
    }

    func getConnection(peerId: String, connectionId: String) -> IConnection {
        fatalError("getConnection(peerId:connectionId:) has not been implemented")
    }

    func getMessage(connectionId: String) -> [[String: Any]] {
        fatalError("getMessage(connectionId:) has not been implemented")
    }

    func removeConnection(_ connection: IConnection) {
    }
}

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

struct OfferRequestEntity: Encodable {
    let type: String
    let payload: Payload
    let dst: String
}

extension OfferRequestEntity {
    struct Payload: Encodable {
        let sdp: SDP
        let type: String
        let connectionId: String
        let browser: String
    }
    struct SDP: Encodable {
        let sdp: String
        let type: String
    }
}

struct LocalCandidateRequestEntity: Encodable {
    let type: String
    let payload: Payload
    let dst: String
}

extension LocalCandidateRequestEntity {
    struct Payload: Encodable {
        let candidate: Candidate
        let type: String
        let connectionId: String
    }

    struct Candidate: Encodable {
        let candidate: String
        let sdpMLineIndex: Int32
        let sdpMid: String?
    }
}

class GBPeer: NSObject {
    private let options: PeerOptions

    private var socket: GBPeerSocket?
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

    private var iceGatheringStateRelay = BehaviorRelay<RTCIceGatheringState>(value: .new)
    var stream: RTCMediaStream?
    var track: RTCAudioTrack?
    private var sendOfferAlready = false
    private var pendingCandidates = [RTCIceCandidate]()
    private var localAudioTrack: RTCAudioTrack?
    private var localAudioSource: RTCAudioSource?

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

        GBPeerLogger.shared.debug = options.debug

        initialize(userId)
        trackLifetime()
    }

    private func emitError(_ message: String) {
        delegate?.peerJs(self, onError: GBPeerError(message: message))
    }

    private func emitError(_ error: Error) {
        delegate?.peerJs(self, onError: error)
    }

    func cleanup() {
        destroyServerConnection()
        if let id = id {
            cleanupPeer(id)
        }
        destroyCall()
    }

    func requestReconnect() {
        reconnect()
    }

    func reconfigureAudio() {
        let audioSession = RTCAudioSession.sharedInstance()

        audioSession.lockForConfiguration()
        defer { audioSession.unlockForConfiguration() }

        do {
            try audioSession.setCategory(
                    AVAudioSession.Category.playAndRecord.rawValue,
                    with: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth, .allowAirPlay]
            )
            try audioSession.setMode(AVAudioSession.Mode.videoChat.rawValue)

            let currentRoute = AVAudioSession.sharedInstance().currentRoute
            let isWiredSpeakerConnected = currentRoute.outputs.contains { $0.portType == .headphones }
            let isBluetoothConnected = currentRoute.outputs.contains {
                $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
            }

            if isBluetoothConnected {
                try audioSession.overrideOutputAudioPort(.none)
            } else if isWiredSpeakerConnected {
                try audioSession.overrideOutputAudioPort(.none)
            } else {
                try audioSession.overrideOutputAudioPort(.speaker)
            }
            try audioSession.setActive(true)
        } catch {
            Printt.shared.print("Client RTC - set audio error")
            Printt.shared.print(error)
        }
    }

    func dumpCall(id: String, _ servers: [RTCIceServer]) {
        sendOfferAlready = false
        pendingCandidates.removeAll()
        // MARK: - Create PeerConnection
        destroyCall()
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
                ],
                optionalConstraints: [
                    "Dt1sSrtpKeyAgreement": kRTCMediaConstraintsValueTrue
                ]
        )
        let rtcPeerFactory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        let config = RTCConfiguration()
        config.iceServers = servers
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        let rtcPeer = rtcPeerFactory.peerConnection(with: config, constraints: constraints, delegate: nil)!
        self.rtcPeer = rtcPeer
        self.rtcPeerFactory = rtcPeerFactory

        GBPeerLogger.shared.log("Creating RTCPeerConnection.")
        GBPeerLogger.shared.log("Listening for ICE candidates.")
        GBPeerLogger.shared.log("Listening for data channel")
        GBPeerLogger.shared.log("Listening for remote stream.")
        rtcPeer.delegate = self

        // MARK: - Add Track

        GBPeerLogger.shared.log("add tracks from stream 5f85738a-0ec5-4cba-a26f-60c3b057d338 to peer connection")
        let audioConstrains = RTCMediaConstraints(
                mandatoryConstraints: [
                    kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
                ],
                optionalConstraints: [
                    "Dt1sSrtpKeyAgreement": kRTCMediaConstraintsValueTrue
                ]
        )
        let audioSource = rtcPeerFactory.audioSource(with: audioConstrains)
        let audioTrack = rtcPeerFactory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.source.volume = 10
        rtcPeer.add(audioTrack, streamIds: ["audio0"])
        self.localAudioTrack = audioTrack
        self.localAudioSource = audioSource

        let remotePeerId = id
        let connectionId = "mc_\(randomToken1(11))"
        self.remotePeerId = remotePeerId
        self.connectionId = connectionId
        GBPeerLogger.shared.log("add connection media:\(connectionId) to peerId:\(remotePeerId)")
        reconfigureAudio()

        // MARK: - Create local offer

        let offerRx: Single<RTCSessionDescription> = Single.create { observer in
            rtcPeer.offer(
                    for: RTCMediaConstraints(
                            mandatoryConstraints: [
                                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
                            ],
                            optionalConstraints: [
                                "Dt1sSrtpKeyAgreement": kRTCMediaConstraintsValueTrue
                            ]
                    )
            ) { (sdp, error) in
                if let error = error {
                    observer(.error(error))
                } else if let sdp = sdp {
                    observer(.success(sdp))
                } else {
                    observer(.error(UnknownError()))
                }
            }
            return Disposables.create()
        }
        let offer: RTCSessionDescription
        do {
            try offer = offerRx.toBlocking().first()!
        } catch {
            fatalError("Error Create offer \(error)")
        }
        GBPeerLogger.shared.log("Created offer")

        // MARK: - Wait ICE To complete

        GBPeerLogger.shared.log("Ready to send offer")

        // MARK: - SEND OFFER

        let offerEntity = OfferRequestEntity(
                type: "OFFER",
                payload: .init(
                        sdp: .init(
                                sdp: offer.sdp,
                                type: "offer"
                        ),
                        type: "media",
                        connectionId: connectionId,
                        browser: UIDevice.current.userInterfaceIdiom == .pad
                                ? "iPad"
                                : UIDevice.current.userInterfaceIdiom == .phone
                                ? "iPhone"
                                : "iPod"
                ),
                dst: remotePeerId
        )
        let offerEncoder = JSONEncoder()
        let offerJson: String
        do {
            let offerData = try offerEncoder.encode(offerEntity)
            offerJson = String(data: offerData, encoding: .utf8)!
        } catch {
            fatalError("Create Offer json failed")
        }
        socket?.send(offerJson)

        // MARK: - Set local description

        let setLocalDescriptionRx: Completable = Completable.create { observer in
            rtcPeer.setLocalDescription(offer, completionHandler: { (error) in
                if let error = error {
                    observer(.error(error))
                } else {
                    observer(.completed)
                }
            })
            return Disposables.create()
        }
        do {
            try setLocalDescriptionRx.andThen(Single.just(true)).toBlocking().first()
        } catch {
            fatalError("Error Set local description \(error)")
        }
    }

    private func destroyCall() {
        rtcPeer?.close()
        RTCCleanupSSL()
    }
}

extension GBPeer: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("WebRTC - didChange stateChanged - \(stateChanged) | Called when the SignalingState changed.")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("WebRTC - didAdd stream | Called when media is received on a new stream from remote peer.")

        GBPeerLogger.shared.log("Received remote stream")

        GBPeerLogger.shared.log("add stream \(stream.streamId) to media connection \(connectionId ?? "-")")

        if let track = stream.audioTracks.first {
            track.isEnabled = true
            track.source.volume = 10
            self.stream = stream
            self.track = track
            reconfigureAudio()
        } else {
            GBPeerLogger.shared.log("Weird looking stream")
        }

        GBPeerLogger.shared.log("Receiving stream")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("WebRTC - didRemove stream | Called when a remote peer closes a stream.")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("WebRTC - peerConnectionShouldNegotiate | Called when negotiation is needed, for example ICE has restarted.")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("WebRTC - didChange newState \(newState) | Called any time the IceConnectionState changes.")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("WebRTC - didChange newState \(newState) | Called any time the IceGatheringState changes")
        iceGatheringStateRelay.accept(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("WebRTC - didGenerate candidate | New ice candidate has been found.")

        let peerId = remotePeerId!
        let connectionId = connectionId!
        let connectionType = "media"

        guard !candidate.sdp.isEmpty else {
            return
        }

        GBPeerLogger.shared.log("Received ICE candidates for \(peerId):\(candidate.sdp)")

        if sendOfferAlready {
            sendOffer(candidate)
        } else {
            pendingCandidates.append(candidate)
        }
    }

    private func sendOffer(_ candidate: RTCIceCandidate) {
        let peerId = remotePeerId!
        let connectionId = connectionId!
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
            candidateJson = String(data: candidateData, encoding: .utf8)!
        } catch {
            fatalError("Create Candidate json failed")
        }
        socket?.send(candidateJson)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("WebRTC - didRemove candidates | Called when a group of local Ice candidates have been removed.")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("WebRTC - didOpen dataChannel | New data channel has been opened.")
    }
}

// MARK: - Private

private extension GBPeer {
    func initialize(_ id: String) {
        self.id = id
        socket?.start(id: id, token: options.token ?? randomToken)
    }

    func cleanupPeer(_ id: String) {

    }
}

// MARK: - Connectivity

private extension GBPeer {
    func disconnect() {
        if disconnected {
            return
        }

        let currentId = id

        GBPeerLogger.shared.log("Disconnect peer with ID:\(currentId ?? "-")")

        disconnected = true
        open = false

        socket?.close()

        lastServerId = currentId
        id = nil

        delegate?.peerJs(self, onDisconnected: currentId)
    }

    func destroy() {
        if destroyed {
            return
        }

        GBPeerLogger.shared.log("Destroy peer with ID:\(id ?? "-")")

        disconnect()
        cleanup()

        destroyed = true

        delegate?.peerJs(self, onClose: ())
    }

    func reconnect() {
        if disconnected && !destroyed,
           let lastServerId = lastServerId {
            GBPeerLogger.shared.log("Attempting reconnection to server with ID \(lastServerId)")
            disconnected = false
            initialize(lastServerId)
        } else if destroyed {
            GBPeerLogger.shared.log("This peer cannot reconnect to the server. It has already been destroyed.")
        } else if !disconnected && !open {
            // Do nothing. We're still connecting the first time.
            GBPeerLogger.shared.log("In a hurry? We're still trying to make the initial connection!")
        } else {
            GBPeerLogger.shared.log("Peer \(id ?? "-") cannot reconnect because it is not disconnected from the server!")
        }
    }

    func abort(_ error: Error?) {
        GBPeerLogger.shared.log("Aborting!")

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
}

// MARK: - Data

private extension GBPeer {
    func handleMessage(_ message: GBPeerSocket.StringMessageResponse) {
        let type = message.decodedResponse["type"] as? String

        switch (type) {
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
                GBPeerLogger.shared.log("Received leave message from \(peerId ?? "-")")
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
                GBPeerLogger.shared.log("You received a malformed message from \(peerId ?? "-") of type \(type ?? "-")")
            }
            if type == "ANSWER" {
                guard let payload = message.decodedResponse["payload"] as? [String: Any],
                      let sdp = payload["sdp"] as? [String: Any],
                      let sdpString = sdp["sdp"] as? String,
                      let sdpType = sdp["type"] as? String else {
                    fatalError("ANSWER call should have payload and sdp")
                }
                let remoteSdp = RTCSessionDescription(type: sdpType == "answer" ? .answer : .prAnswer, sdp: sdpString)
                let peerConnection = rtcPeer!

                GBPeerLogger.shared.log("Setting remote description \(sdpString)")

                let setRemoteDescriptionRx: Completable = Completable.create { observer in
                    peerConnection.setRemoteDescription(remoteSdp, completionHandler: { (error) in
                        if let error = error {
                            observer(.error(error))
                        } else {
                            observer(.completed)
                        }
                    })
                    return Disposables.create()
                }
                do {
                    try setRemoteDescriptionRx.andThen(Single.just(true)).toBlocking().first()
                } catch {
                    fatalError("Error Set remote description \(error)")
                }

                GBPeerLogger.shared.log("Set remoteDescription:\(type ?? "-") for:\(remotePeerId ?? "-")")

                sendOfferAlready = true
                let pending = Array(pendingCandidates)
                pendingCandidates.removeAll()
                for p in pending {
                    sendOffer(p)
                }
            } else if type == "CANDIDATE" {
                if rtcPeer?.remoteDescription == nil {
                    fatalError("Remote description must be set")
                }
                guard let payload = message.decodedResponse["payload"] as? [String: Any],
                      let candidate = payload["candidate"] as? [String: Any],
                      let candidateString = candidate["candidate"] as? String else {
                    fatalError("CANDIDATE call should have payload and candidate")
                }
                GBPeerLogger.shared.log("handleCandidate: \(candidateString)")

                let sdpMLineIndex = candidate["sdpMLineIndex"] as? Int
                let sdpMLineIndex32: Int32
                if let sdpMLineIndex {
                    sdpMLineIndex32 = Int32(sdpMLineIndex)
                } else {
                    sdpMLineIndex32 = 0
                }
                let sdpMid = candidate["sdpMid"] as? String
                let peerConnection = rtcPeer!
                let provider = self

                let ice = RTCIceCandidate(sdp: candidateString, sdpMLineIndex: sdpMLineIndex32, sdpMid: sdpMid)

                let setIceCandidateRx: Completable = Completable.create { observer in
                    peerConnection.add(ice, completionHandler: { (error) in
                        if let error = error {
                            observer(.error(error))
                        } else {
                            observer(.completed)
                        }
                    })
                    return Disposables.create()
                }
                do {
                    try setIceCandidateRx.andThen(Single.just(true)).toBlocking().first()
                } catch {
                    fatalError("Error Set ice candidate \(error)")
                }
                GBPeerLogger.shared.log("Added ICE candidate for:\(remotePeerId ?? "-")")
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
    func createServerConnection() -> GBPeerSocket {
        destroyServerConnection()
        let socket = GBPeerSocket(
                secure: options.secure,
                host: options.host ?? kHostDefault,
                port: options.port ?? kPortDefault,
                path: options.path ?? kPathDefault,
                key: options.key ?? kKeyDefault,
                pingInterval: options.pingInterval ?? kPingIntervalDefault
        )

        return socket
    }

    func destroyServerConnection() {
        socket?.cleanup()
        socket?.delegate = nil
        socket = nil
    }
}

extension GBPeer: GBPeerSocketDelegate {
    func socketJs(onDisconnected: ()) {
        if disconnected {
            return
        }

        emitError("Lost connection to server.")
        disconnect()
    }

    func socketJs(onNewMessage data: GBPeerSocket.StringMessageResponse) {
        handleMessage(data)
    }

    func socketJs(onNewMessage: Data) {
        GBPeerLogger.shared.log("onNewMessage(Data) not implemented yet")
    }

    func socketJs(onError error: Error?) {
        abort(error)
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
