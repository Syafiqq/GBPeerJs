//
// Created by engineering on 27/6/23.
//

import Foundation
import WebRTC
import RxSwift

public protocol GBPeerMediaConnectionDelegate: AnyObject {
    func mediaConnection(_: GBPeerMediaConnection, onRemoteStreamAdded: RTCMediaStream)
    func mediaConnection(_: GBPeerMediaConnection, onClose: ())
    func mediaConnection(_: GBPeerMediaConnection, onError: Error)
    func mediaConnection(_: GBPeerMediaConnection, onIceStateChanged: RTCIceConnectionState)
}

public class GBPeerMediaConnection: GBPeerConnection {
    private static let idPrefix = "mc_"

    private var open = false
    private let logger: ILogger = Logger.shared

    private var negotiator: INegotiator?
    private var localStream: RTCMediaStream?
    private var remoteStream: RTCMediaStream?

    private let remoteOfferPayload: [String: Any]

    private var classBag = DisposeBag()

    var peer: String
    var connectionId: String
    var type: ConnectionType = .media

    var originator: Bool
    var peerConnection: RTCPeerConnection?

    weak var provider: IPeer?
    public weak var delegate: GBPeerMediaConnectionDelegate?
    private var mediaOfferConstraint: RTCMediaConstraints?

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
        negotiator = Negotiator(connection: self, logger: logger)

        if let stream = stream {
            negotiator?.startConnection(
                            stream: stream,
                            originator: true,
                            mediaOfferConstraint: stream.offerConstraint,
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
                                self?.provider?.emitError(error)
                            }
                    )
                    .disposed(by: classBag)
        }
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

                let constraint: RTCMediaConstraints
                if let mediaOfferConstraint = mediaOfferConstraint {
                    constraint = mediaOfferConstraint
                } else {
                    constraint = RTCMediaConstraints(
                            mandatoryConstraints: nil,
                            optionalConstraints: nil
                    )
                }

                negotiator?.handleSDP(
                                type: type,
                                sdp: sdp,
                                mediaOfferConstraint: constraint
                        )
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                        .subscribe(
                                onCompleted: { [weak self] in
                                    self?.logger.log("Success handle SDP")
                                },
                                onError: { [weak self] error in
                                    self?.logger.log("Failed to handle SDP")
                                    self?.provider?.emitError(error)
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

        negotiator?.startConnection(
                        stream: stream,
                        originator: false,
                        mediaOfferConstraint: stream.offerConstraint,
                        remoteOfferSdp: (remoteOfferPayload["sdp"] as? String) ?? ""
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
    func setPeerConnection(_ peer: RTCPeerConnection) {
        peerConnection = peer
    }

    func unsetPeerConnection() {
        peerConnection = nil
    }

    func addStream(_ stream: RTCMediaStream) {
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
