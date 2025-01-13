//
// Created by engineering on 27/6/23.
//

import Foundation
import LiveKitWebRTC
import RxSwift

public protocol GBPeerMediaConnectionDelegate: AnyObject {
    func mediaConnection(_ sender: GBPeerMediaConnection, onRemoteStreamAdded: LKRTCMediaStream)
    func mediaConnection(_ sender: GBPeerMediaConnection, onClose: ())
    func mediaConnection(_ sender: GBPeerMediaConnection, onError: Error)
    func mediaConnection(_ sender: GBPeerMediaConnection, onIceStateChanged: RTCIceConnectionState)
}

public class GBPeerMediaConnection: GBPeerConnection {
    private static let idPrefix = "mc_"

    private var open = false
    private let logger: ILogger = Logger.shared

    private var negotiator: INegotiator?
    private var localStream: LKRTCMediaStream?
    private var remoteStream: LKRTCMediaStream?

    private let remoteOfferPayload: [String: Any]

    private var classBag = DisposeBag()

    var peer: String
    var connectionId: String
    var type: ConnectionType = .media

    var originator: Bool
    var peerConnection: LKRTCPeerConnection?

    weak var provider: IPeer?
    public weak var delegate: GBPeerMediaConnectionDelegate?
    private var mediaOfferConstraint: LKRTCMediaConstraints?

    init(
            peer: String,
            provider: IPeer?,
            connectionId: String?,
            stream: GBPeerMediaStream?,
            remoteOfferPayload: [String: Any]
    ) {
        self.peer = peer
        self.provider = provider
        self.remoteOfferPayload = remoteOfferPayload
        originator = true

        localStream = stream?.stream
        self.connectionId = connectionId ?? "\(Self.idPrefix)\(Util.randomToken(11))"
        negotiator = Negotiator(connection: self)

        if let stream = stream {
            let sdp = (remoteOfferPayload["sdp"] as? [String: Any]) ?? [:]
            negotiator?.startConnection(
                            stream: stream,
                            originator: true,
                            mediaOfferConstraint: stream.offerConstraint,
                            remoteOfferSdp: (sdp["sdp"] as? String) ?? "",
                            remoteOfferSdpType: (sdp["type"] as? String) ?? ""
                    )
                    .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                    .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                    .subscribe(
                            onCompleted: { [weak self] in
                                self?.logger.log("Success Start IConnection")
                            },
                            onError: { [weak self] error in
                                self?.logger.log("Failed to start connection")
                                self?.provider?.emitError(error)
                            }
                    )
                    .disposed(by: classBag)
        }

        trackLifetime()
    }

    public func answer(stream: GBPeerMediaStream) {
        doAnswer(stream: stream)
    }

    public func close() {
        doClose()
    }

    func cleanup() {
        doClose()
        classBag = DisposeBag()
    }

    deinit {
        cleanup()
    }
}

private extension GBPeerMediaConnection {
    func doAddStream(_ remoteStream: LKRTCMediaStream) {
        logger.log("Receiving stream", remoteStream.streamId)

        self.remoteStream = remoteStream
        delegate?.mediaConnection(self, onRemoteStreamAdded: remoteStream) // Should we call this `open`?
    }

    // swiftlint:disable:next function_body_length
    func doHandleMessage(message: [String: Any]) {
        let type = message["type"] as? String

        switch type {
        case ServerMessageType.answer.rawValue:
            // Forward to negotiator
            if let type = type,
               let payload = message["payload"] as? [String: Any],
               let sdp = payload["sdp"] as? [String: Any] {

                let constraint: LKRTCMediaConstraints
                if let mediaOfferConstraint = mediaOfferConstraint {
                    constraint = mediaOfferConstraint
                } else {
                    constraint = LKRTCMediaConstraints(
                            mandatoryConstraints: nil,
                            optionalConstraints: nil
                    )
                }

                negotiator?.handleSDP(
                                type: type,
                                sdp: (sdp["sdp"] as? String) ?? "",
                                sdpType: (sdp["type"] as? String) ?? "",
                                mediaOfferConstraint: constraint
                        )
                        .do(
                                onError: { [weak self] error in
                                    self?.logger.log("Failed to handle SDP", error)
                                },
                                onCompleted: { [weak self] in
                                    self?.logger.log("Success handle SDP")
                                }
                        )
                        .andThen(
                                Completable.deferred { [weak self] in
                                    // Retrieve lost messages stored because PeerConnection not set up.
                                    let messages: [[String: Any]]
                                    if let connectionId = self?.connectionId {
                                        messages = self?.provider?.getMessages(connectionId: connectionId) ?? []
                                    } else {
                                        messages = []
                                    }

                                    for message in messages {
                                        self?.doHandleMessage(message: message)
                                    }

                                    return Completable.empty()
                                }
                        )
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribe(
                                onCompleted: { [weak self] in
                                    self?.logger.log("Success answer")
                                },
                                onError: { [weak self] error in
                                    self?.logger.log("Failed to answer")
                                    self?.provider?.emitError(error)
                                }
                        )
                        .disposed(by: classBag)
                open = true
            }
        case ServerMessageType.candidate.rawValue:
            if let peerConnection = peerConnection,
               peerConnection.remoteDescription == nil {
                provider?.storeMessage(connectionId: connectionId, message: message)
            } else if let payload = message["payload"] as? [String: Any],
                      let candidate = payload["candidate"] as? [String: Any],
                      let candidateString = candidate["candidate"] as? String {
                let sdpMLineIndex = candidate["sdpMLineIndex"] as? Int
                let sdpMLineIndex32: Int32
                if let sdpMLineIndex {
                    sdpMLineIndex32 = Int32(sdpMLineIndex)
                } else {
                    sdpMLineIndex32 = 0
                }
                let sdpMid = candidate["sdpMid"] as? String
                negotiator?.handleCandidate(
                                LKRTCIceCandidate(
                                        sdp: candidateString,
                                        sdpMLineIndex: sdpMLineIndex32,
                                        sdpMid: sdpMid
                                )
                        )
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribe(
                                onCompleted: { [weak self] in
                                    self?.logger.log("Success handle Candidate")
                                },
                                onError: { [weak self] error in
                                    self?.logger.log("Failed to handle candidate")
                                    self?.provider?.emitError(error)
                                }
                        )
                        .disposed(by: classBag)
                open = true
            }
        default:
            logger.warn("Unrecognized message type:\(type ?? "-") from peer:\(peer)")
        }
    }

    func doAnswer(stream: GBPeerMediaStream) {
        if localStream != nil {
            logger.warn("Local stream already exists on this GBPeerMediaConnection. Are you answering a call twice?")
            return
        }

        localStream = stream.stream

        /*if options && options.sdpTransform {
            this.options.sdpTransform = options.sdpTransform;
        }*/

        let sdp = (remoteOfferPayload["sdp"] as? [String: Any]) ?? [:]
        negotiator?.startConnection(
                        stream: stream,
                        originator: false,
                        mediaOfferConstraint: stream.offerConstraint,
                        remoteOfferSdp: (sdp["sdp"] as? String) ?? "",
                        remoteOfferSdpType: (sdp["type"] as? String) ?? ""
                )
                .andThen(
                        Completable.deferred { [weak self] in
                            // Retrieve lost messages stored because PeerConnection not set up.
                            let messages: [[String: Any]]
                            if let connectionId = self?.connectionId {
                                messages = self?.provider?.getMessages(connectionId: connectionId) ?? []
                            } else {
                                messages = []
                            }

                            for message in messages {
                                self?.doHandleMessage(message: message)
                            }

                            return Completable.empty()
                        }
                )
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribe(
                        onCompleted: { [weak self] in
                            self?.open = true
                            self?.logger.log("Success answer")
                        },
                        onError: { [weak self] error in
                            self?.logger.log("Failed to answer")
                            self?.provider?.emitError(error)
                        }
                )
                .disposed(by: classBag)
    }

    /** Allows user to close connection. */
    func doClose() {
        if negotiator != nil {
            negotiator?.cleanup()
            negotiator = nil
        }

        localStream = nil
        remoteStream = nil

        if provider != nil {
            provider?.removeConnection(self)
            provider = nil
        }

        /*if (this.options && this.options._stream) {
            this.options._stream = null;
        }*/

        guard open else {
            return
        }

        open = false

        delegate?.mediaConnection(self, onClose: ())
    }
}

extension GBPeerMediaConnection: IConnection {
    func setPeerConnection(_ peer: LKRTCPeerConnection) {
        peerConnection = peer
    }

    func unsetPeerConnection() {
        peerConnection = nil
    }

    func addStream(_ stream: LKRTCMediaStream) {
        doAddStream(stream)
    }

    func requestClose() {
        doClose()
    }

    func emitError(_ error: Error) {
        delegate?.mediaConnection(self, onError: error)
    }

    func emitIceStateChanged(_ state: RTCIceConnectionState) {
        delegate?.mediaConnection(self, onIceStateChanged: state)
    }

    func handleMessage(message: [String: Any]) {
        doHandleMessage(message: message)
    }
}

import LifetimeTracker

extension GBPeerMediaConnection: LifetimeTrackable {
    public class var lifetimeConfiguration: LifetimeConfiguration {
        LifetimeConfiguration(maxCount: 1)
    }
}
