//
// Created by engineering on 27/6/23.
//

import Foundation
import WebRTC
import RxSwift

protocol MediaConnectionDelegate: AnyObject {
    func mediaConnection(_: MediaConnection, onRemoteStreamAdded: RTCMediaStream)
}

class MediaConnection: IConnection {
    private static let idPrefix = "mc_"

    var peer: String
    var connectionId: String
    var type: ConnectionType = .media

    var originator: Bool

    weak var provider: PeerProvider?
    weak var delegate: MediaConnectionDelegate?
    var peerConnection: RTCPeerConnection?

    private var classBag = DisposeBag()

    private var open = false
    private let localStream: RTCMediaStream?
    private var remoteStream: RTCMediaStream?
    private let logger: ILogger
    private var negotiator: INegotiator?

    init(
            peer: String,
            provider: PeerProvider?,
            connectionId: String?,
            stream: RTCMediaStream,
            logger: ILogger
    ) {
        self.peer = peer
        self.provider = provider
        self.logger = logger
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
                    )
            )
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

    func emitError(_ error: Error) {
    }

    func close() {
    }

    func emitIceStateChanged(_ state: RTCIceConnectionState) {
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
            logger.warn("Unrecognized message type:\(type ?? "-") from peer:\(peer)");
        }
    }
}
