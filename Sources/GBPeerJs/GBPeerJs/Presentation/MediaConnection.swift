//
// Created by engineering on 27/6/23.
//

import Foundation
import WebRTC
import RxSwift

protocol MediaConnectionDelegate: AnyObject {
    func mediaConnection(_: MediaConnection, onRemoteStreamAdded: RTCMediaStream)
    func mediaConnection(_: MediaConnection, onClose: ())
    func mediaConnection(_: MediaConnection, onError: Error)
}

class MediaConnection: IConnection {
    private static let idPrefix = "mc_"

    var peer: String
    var connectionId: String
    var type: ConnectionType = .media

    var originator: Bool

    weak var provider: IPeer?
    weak var delegate: MediaConnectionDelegate?
    var peerConnection: RTCPeerConnection?

    private var classBag = DisposeBag()

    private var open = false
    private var localStream: RTCMediaStream?
    private var remoteStream: RTCMediaStream?
    private let logger: ILogger
    private var negotiator: INegotiator?
    private var remoteOfferPayload: [String: Any] = [:]

    init(
            peer: String,
            provider: IPeer?,
            connectionId: String?,
            stream: RTCMediaStream?,
            logger: ILogger,
            remoteOfferPayload: [String: Any]
    ) {
        self.peer = peer
        self.provider = provider
        self.logger = logger
        self.remoteOfferPayload = remoteOfferPayload
        originator = true

        localStream = stream
        self.connectionId = connectionId ?? "\(Self.idPrefix)\(Util.randomToken(11))"
        negotiator = Negotiator(connection: self, logger: logger)

        if let stream = localStream {
            negotiator?.startConnection(
                            stream: stream,
                            originator: true,
                            originatorConstraint: nil,
                            data: NegotiatorEntity(
                                    peerFactory: RTCPeerConnectionFactory(),
                                    peerConfig: RTCConfiguration(),
                                    peerConstraint: RTCMediaConstraints(
                                            mandatoryConstraints: nil,
                                            optionalConstraints: nil
                                    )
                            ),
                            remoteOfferSdp: (remoteOfferPayload["sdp"] as? String) ?? ""
                    )
                    .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                    .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                    .subscribe(
                            onCompleted: { [weak self] in
                                self?.logger.log("Success Start IConnection")
                            },
                            onError: { [weak self] error in
                                self?.logger.log("Failed to start connection")
                                self?.emitError(error)
                            }
                    )
                    .disposed(by: classBag)
        }
    }

    func setPeerConnection(_ peer: RTCPeerConnection) {
        peerConnection = peer
    }

    func unsetPeerConnection() {
        peerConnection = nil
    }

    func addStream(_ stream: RTCMediaStream) {
        doAddStream(stream)
    }

    func close() {
        doClose()
    }

    func emitError(_ error: Error) {
        delegate?.mediaConnection(self, onError: error)
    }

    func emitIceStateChanged(_ state: RTCIceConnectionState) {
    }

    func handleMessage(message: [String: Any]) {
        doHandleMessage(message: message)
    }

    deinit {
        classBag = DisposeBag()
    }
}

private extension MediaConnection {
    func doAddStream(_ remoteStream: RTCMediaStream) {
        logger.log("Receiving stream", remoteStream)

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
               let sdp = payload["sdp"] as? String {
                negotiator?.handleSDP(
                                type: type,
                                sdp: sdp,
                                answerMediaConstraint: nil
                        )
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribe(
                                onCompleted: { [weak self] in
                                    self?.logger.log("Success handle SDP")
                                },
                                onError: { [weak self] error in
                                    self?.logger.log("Failed to handle SDP")
                                    self?.emitError(error)
                                }
                        )
                        .disposed(by: classBag)
                open = true
            }
        case ServerMessageType.candidate.rawValue:
            if let payload = message["payload"] as? [String: Any],
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
                                RTCIceCandidate(
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
                                    self?.emitError(error)
                                }
                        )
                        .disposed(by: classBag)
                open = true
            }
        default:
            logger.warn("Unrecognized message type:\(type ?? "-") from peer:\(peer)")
        }
    }

    func doAnswer(stream: RTCMediaStream?) {
        if localStream != nil {
            logger.warn("Local stream already exists on this MediaConnection. Are you answering a call twice?")
            return
        }

        localStream = stream

        /*if options && options.sdpTransform {
            this.options.sdpTransform = options.sdpTransform;
        }*/

        negotiator?.startConnection(
                        stream: stream,
                        originator: false,
                        originatorConstraint: nil,
                        data: NegotiatorEntity(
                                peerFactory: RTCPeerConnectionFactory(),
                                peerConfig: RTCConfiguration(),
                                peerConstraint: RTCMediaConstraints(
                                        mandatoryConstraints: nil,
                                        optionalConstraints: nil
                                )
                        ),
                        remoteOfferSdp: (remoteOfferPayload["sdp"] as? String) ?? ""
                )
                .andThen(
                        Completable.deferred { [weak self] in
                            // Retrieve lost messages stored because PeerConnection not set up.
                            let connectionId = self?.connectionId ?? ""
                            let messages = self?.provider?.getMessages(connectionId: connectionId) ?? []

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
                            self?.emitError(error)
                        }
                )
                .disposed(by: classBag)
    }

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
