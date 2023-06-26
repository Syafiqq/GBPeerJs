//
// Created by engineering on 25/6/23.
//

import Foundation
import WebRTC
import RxSwift

struct IceCandidate: Encodable {
    let candidate: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
}

enum ConnectionType: String {
    // swiftlint:disable explicit_enum_raw_value
    case media
    // swiftlint:enable explicit_enum_raw_value
}

enum Util {
    static func browser() -> String {
        UIDevice.current.userInterfaceIdiom == .pad
                ? "iPad"
                : UIDevice.current.userInterfaceIdiom == .phone
                ? "iPhone"
                : "iPod"
    }
}

enum ServerMessageType: String {
    // @formatter:off
    case heartbeat  = "HEARTBEAT"
    case candidate  = "CANDIDATE"
    case offer      = "OFFER"
    case answer     = "ANSWER"
    case open       = "OPEN" // The connection to the server is open.
    case error      = "ERROR" // Server error.
    case idTaken    = "ID-TAKEN" // The selected ID is taken.
    case invalidKey = "INVALID-KEY" // The given API key cannot be found.
    case leave      = "LEAVE" // Another peer has closed its connection to this peer.
    case expire     = "EXPIRE" // The offer sent to a peer has expired without response.
    // @formatter:on
}

struct OfferRequestEntity: Encodable {
    let type: String
    let payload: Payload
    let dst: String
}

struct NegotiatorEntity {
    var peerFactory: RTCPeerConnectionFactory
    var peerConfig: RTCConfiguration
    var peerConstraint: RTCMediaConstraints
}

protocol SocketProvider: AnyObject {
    func send(_ message: String)
}

protocol PeerProvider: AnyObject {
    var socket: SocketProvider? { get }
}

protocol Connection: AnyObject {
    var peer: String { get }
    var connectionId: String { get }
    var type: ConnectionType { get }
    var provider: PeerProvider? { get }
    var originator: Bool { get }
    var peerConnection: RTCPeerConnection { get }

    func setPeerConnection(_ peer: RTCPeerConnection)
    func addStream(_ stream: RTCMediaStream)
}

// swiftlint:disable:next type_body_length
class Negotiator: NSObject {
    weak var connection: Connection?
    let logger: ILogger

    init(connection: Connection, logger: ILogger) {
        self.connection = connection
        self.logger = logger
    }

    func startConnection(data: NegotiatorEntity) -> Completable {
        doStartConnection(data: data)
    }

    func addTracksToConnection(
            stream: RTCMediaStream,
            peerConnection: RTCPeerConnection
    ) {
        logger.log("add tracks from stream \(stream.streamId) to peer initialization")

        /*guard (peerConnection.canAddTrack) else {
            logger.error("Your browser does't support RTCPeerConnection#addTrack. Ignored.")
            return
        }*/

        stream.audioTracks.forEach {
            peerConnection.add($0, streamIds: [stream.streamId])
        }
    }

    func addStreamToMediaConnection(
            stream: RTCMediaStream,
            mediaConnection: Connection
    ) {
        logger.log("add stream \(stream.streamId) to media connection \(mediaConnection.connectionId)")

        mediaConnection.addStream(stream);
    }

    // swiftlint:disable:next function_body_length
    func makeOffer(
            mediaConstraint: RTCMediaConstraints
    ) -> Completable {
        func createOfferAsync(mediaConstraint: RTCMediaConstraints) -> Single<RTCSessionDescription> {
            Single.create { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.offer(
                            for: mediaConstraint,
                            completionHandler: { [weak self] description, error in
                                if self == nil {
                                    observer(.error(RxError.disposed(object: Self.self)))
                                } else if let error = error {
                                    observer(.error(
                                            GBPeerJsError.WebRtcLocalOfferErrorReason.createLocalOfferFailed(error)
                                    ))
                                } else if let description = description {
                                    observer(.success(description))
                                } else {
                                    observer(.error(
                                            GBPeerJsError.WebRtcLocalOfferErrorReason.createLocalOfferFailed(nil)
                                    ))
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.WebRtcCommonErrorReason.unknownPeerConnection))
                }
                return Disposables.create()
            }
        }

        func setLocalDescriptionAsync(offer: RTCSessionDescription) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.setLocalDescription(
                            offer,
                            completionHandler: { [weak self] error in
                                if self == nil {
                                    observer(.error(RxError.disposed(object: Self.self)))
                                } else if let error = error {
                                    observer(.error(
                                            GBPeerJsError.WebRtcLocalOfferErrorReason.setLocalDescriptionFailed(error)
                                    ))
                                } else {
                                    observer(.completed)
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.WebRtcCommonErrorReason.unknownPeerConnection))
                }
                return Disposables.create()
            })
        }

        return Completable.create(
                subscribe: { [weak self] observer in
                    guard let self = self else {
                        observer(.error(RxError.disposed(object: Self.self)))
                        return Disposables.create()
                    }

                    var bag = [Disposable]()
                    let disposable = createOfferAsync(mediaConstraint: mediaConstraint)
                            .do(
                                    onSuccess: { [weak self] _ in
                                        self?.logger.log("Created offer.")
                                    },
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to create offer, ", error)
                                    }
                            )
                            /*.map {
                                // Modify offer
                                if self.connection.options.sdpTransform,
                                   typeof self.connection.options.sdpTransform === "function" {
                                    offer.sdp =
                                            self.connection.options.sdpTransform(offer.sdp) || offer.sdp
                                }
                            }*/
                            .flatMap({ offer in
                                setLocalDescriptionAsync(offer: offer)
                                        .do(
                                                onError: { [weak self] error in
                                                    self?.logger.log("Failed to setLocalDescription, ", error)
                                                },
                                                onCompleted: { [weak self] in
                                                    let peer = self?.connection?.peer ?? "-"
                                                    self?.logger.log("Set localDescription:\(offer.sdp) for:\(peer)")
                                                }
                                        )
                                        .andThen(Single.just(offer))
                            })
                            .subscribe(
                                    onSuccess: { [weak self] (offer: RTCSessionDescription) in
                                        guard let self = self else {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                            return
                                        }

                                        /*if (self.connection.type === ConnectionType.Data) {
                                            const dataConnection = <DataConnection > (<unknown > self.connection)

                                            payload = {
                                                ...payload,
                                                label: dataConnection.label,
                                                reliable: dataConnection.reliable,
                                                serialization: dataConnection.serialization,
                                            }
                                        }*/

                                        let offerEntity = OfferRequestEntity(
                                                type: ServerMessageType.offer.rawValue,
                                                payload: OfferRequestEntity.Payload(
                                                        sdp: OfferRequestEntity.SDP(
                                                                sdp: offer.sdp,
                                                                type: RTCSessionDescription.string(for: offer.type)
                                                        ),
                                                        type: self.connection?.type.rawValue ?? "",
                                                        connectionId: self.connection?.connectionId ?? "",
                                                        browser: Util.browser()
                                                ),
                                                dst: self.connection?.peer ?? ""
                                        )

                                        let offerEncoder = JSONEncoder()
                                        do {
                                            let offerData = try offerEncoder.encode(offerEntity)
                                            if let result = String(data: offerData, encoding: .utf8) {
                                                self.connection?.provider?.socket?.send(result)
                                                observer(.completed)
                                            } else {
                                                observer(.error(GBPeerJsError.webRtcLocalOfferError(
                                                        reason: .submitLocalOfferFailed(nil)
                                                )))
                                            }
                                        } catch {
                                            observer(.error(GBPeerJsError.webRtcLocalOfferError(
                                                    reason: .submitLocalOfferFailed(error)
                                            )))
                                        }
                                    },
                                    onError: { [weak self] error in
                                        if self == nil {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                        } else if let error = error as? GBPeerJsError.WebRtcLocalOfferErrorReason {
                                            observer(.error(GBPeerJsError.webRtcLocalOfferError(reason: error)))
                                        } else {
                                            observer(.error(GBPeerJsError.webRtcLocalOfferError(
                                                    reason: .unknownError(error)
                                            )))
                                        }
                                    }
                            )
                    bag.append(disposable)
                    return Disposables.create(bag)
                }
        )
    }

    // swiftlint:disable:next function_body_length
    func handleSDP(
            type: String,
            sdp: String,
            answerMediaConstraint: RTCMediaConstraints? = nil
    ) -> Completable {
        func setRemoteDescriptionAsync(offer: RTCSessionDescription) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.setRemoteDescription(
                            offer,
                            completionHandler: { [weak self] error in
                                if self == nil {
                                    observer(.error(RxError.disposed(object: Self.self)))
                                } else if let error = error {
                                    observer(.error(
                                            GBPeerJsError.WebRtcRemoteOfferErrorReason.setRemoteDescriptionFailed(error)
                                    ))
                                } else {
                                    observer(.completed)
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.WebRtcCommonErrorReason.unknownPeerConnection))
                }
                return Disposables.create()
            })
        }

        return Completable.create(
                subscribe: { [weak self] observer in
                    guard let self = self else {
                        observer(.error(RxError.disposed(object: Self.self)))
                        return Disposables.create()
                    }

                    let sdp = RTCSessionDescription(type: RTCSessionDescription.type(for: type), sdp: sdp)
                    logger.log("Setting remote description", sdp.sdp)

                    var bag = [Disposable]()
                    let disposable = setRemoteDescriptionAsync(offer: sdp)
                            .do(
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to setRemoteDescription, ", error)
                                    },
                                    onCompleted: { [weak self] in
                                        let peer = self?.connection?.peer ?? "-"
                                        self?.logger.log("Set remoteDescription:\(type) for:\(peer)")
                                    }
                            )
                            .andThen(
                                    Completable.deferred {
                                        if type == "OFFER" {
                                            let constraint: RTCMediaConstraints
                                            if let answerMediaConstraint = answerMediaConstraint {
                                                constraint = answerMediaConstraint
                                            } else {
                                                constraint = RTCMediaConstraints(
                                                        mandatoryConstraints: nil,
                                                        optionalConstraints: nil
                                                )
                                            }
                                            return self.makeAnswer(mediaConstraint: constraint)
                                        }
                                        return Completable.empty()
                                    }
                            )
                            .subscribe(
                                    onCompleted: { [weak self] in
                                        guard self != nil else {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                            return
                                        }

                                        observer(.completed)
                                    },
                                    onError: { [weak self] error in
                                        if self == nil {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                        } else if let error = error as? GBPeerJsError.WebRtcRemoteOfferErrorReason {
                                            observer(.error(GBPeerJsError.webRtcRemoteOfferError(reason: error)))
                                        } else {
                                            observer(.error(GBPeerJsError.webRtcRemoteOfferError(
                                                    reason: .unknownError(error)
                                            )))
                                        }
                                    }
                            )
                    bag.append(disposable)
                    return Disposables.create(bag)
                }
        )
    }

    // swiftlint:disable:next function_body_length
    func makeAnswer(mediaConstraint: RTCMediaConstraints) -> Completable {
        func createAnswerAsync(mediaConstraint: RTCMediaConstraints) -> Single<RTCSessionDescription> {
            Single.create { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.answer(
                            for: mediaConstraint,
                            completionHandler: { [weak self] description, error in
                                if self == nil {
                                    observer(.error(RxError.disposed(object: Self.self)))
                                } else if let error = error {
                                    observer(.error(
                                            GBPeerJsError.WebRtcLocalAnswerErrorReason.createLocalAnswerFailed(error)
                                    ))
                                } else if let description = description {
                                    observer(.success(description))
                                } else {
                                    observer(.error(
                                            GBPeerJsError.WebRtcLocalAnswerErrorReason.createLocalAnswerFailed(nil)
                                    ))
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.WebRtcCommonErrorReason.unknownPeerConnection))
                }
                return Disposables.create()
            }
        }

        func setLocalDescriptionAsync(answer: RTCSessionDescription) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.setLocalDescription(
                            answer,
                            completionHandler: { [weak self] error in
                                if self == nil {
                                    observer(.error(RxError.disposed(object: Self.self)))
                                } else if let error = error {
                                    observer(.error(
                                            GBPeerJsError.WebRtcLocalAnswerErrorReason.setLocalDescriptionFailed(error)
                                    ))
                                } else {
                                    observer(.completed)
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.WebRtcCommonErrorReason.unknownPeerConnection))
                }
                return Disposables.create()
            })
        }

        return Completable.create(
                subscribe: { [weak self] observer in
                    guard let self = self else {
                        observer(.error(RxError.disposed(object: Self.self)))
                        return Disposables.create()
                    }

                    var bag = [Disposable]()
                    let disposable = createAnswerAsync(mediaConstraint: mediaConstraint)
                            .do(
                                    onSuccess: { [weak self] _ in
                                        self?.logger.log("Created answer.")
                                    },
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to create answer, ", error)
                                    }
                            )
                            /*.map {
                                // Modify answer
                                if self.connection.options.sdpTransform,
                                   typeof self.connection.options.sdpTransform === "function" {
                                    answer.sdp =
                                            self.connection.options.sdpTransform(answer.sdp) || answer.sdp
                                }
                            }*/
                            .flatMap({ answer in
                                setLocalDescriptionAsync(answer: answer)
                                        .do(
                                                onError: { [weak self] error in
                                                    self?.logger.log("Failed to setLocalDescription, ", error)
                                                },
                                                onCompleted: { [weak self] in
                                                    let peer = self?.connection?.peer ?? "-"
                                                    self?.logger.log("Set localDescription:\(answer.sdp) for:\(peer)")
                                                }
                                        )
                                        .andThen(Single.just(answer))
                            })
                            .subscribe(
                                    onSuccess: { [weak self] (answer: RTCSessionDescription) in
                                        guard let self = self else {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                            return
                                        }

                                        let answerEntity = OfferRequestEntity(
                                                type: ServerMessageType.answer.rawValue,
                                                payload: OfferRequestEntity.Payload(
                                                        sdp: OfferRequestEntity.SDP(
                                                                sdp: answer.sdp,
                                                                type: RTCSessionDescription.string(for: answer.type)
                                                        ),
                                                        type: self.connection?.type.rawValue ?? "",
                                                        connectionId: self.connection?.connectionId ?? "",
                                                        browser: Util.browser()
                                                ),
                                                dst: self.connection?.peer ?? ""
                                        )

                                        let answerEncoder = JSONEncoder()
                                        do {
                                            let answerData = try answerEncoder.encode(answerEntity)
                                            if let result = String(data: answerData, encoding: .utf8) {
                                                self.connection?.provider?.socket?.send(result)
                                                observer(.completed)
                                            } else {
                                                observer(.error(GBPeerJsError.webRtcLocalAnswerError(
                                                        reason: .submitLocalAnswerFailed(nil)
                                                )))
                                            }
                                        } catch {
                                            observer(.error(GBPeerJsError.webRtcLocalAnswerError(
                                                    reason: .submitLocalAnswerFailed(error)
                                            )))
                                        }
                                    },
                                    onError: { [weak self] error in
                                        if self == nil {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                        } else if let error = error as? GBPeerJsError.WebRtcLocalAnswerErrorReason {
                                            observer(.error(GBPeerJsError.webRtcLocalAnswerError(reason: error)))
                                        } else {
                                            observer(.error(GBPeerJsError.webRtcLocalAnswerError(
                                                    reason: .unknownError(error)
                                            )))
                                        }
                                    }
                            )
                    bag.append(disposable)
                    return Disposables.create(bag)
                }
        )
    }

    // swiftlint:disable:next function_body_length
    func handleCandidate(_ ice: IceCandidate) -> Completable {
        func addIceCandidateAsync(ice: IceCandidate) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.add(
                            RTCIceCandidate(
                                    sdp: ice.candidate,
                                    sdpMLineIndex: ice.sdpMLineIndex,
                                    sdpMid: ice.sdpMid
                            ),
                            completionHandler: { [weak self] error in
                                if self == nil {
                                    observer(.error(RxError.disposed(object: Self.self)))
                                } else if let error = error {
                                    observer(.error(
                                            GBPeerJsError.WebRtcRemoteIceCandidateErrorReason.setCandidateFailed(error)
                                    ))
                                } else {
                                    observer(.completed)
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.WebRtcCommonErrorReason.unknownPeerConnection))
                }
                return Disposables.create()
            })
        }

        logger.log("handleCandidate: ", ice)

        return Completable.create(
                subscribe: { [weak self] observer in
                    guard let self = self else {
                        observer(.error(RxError.disposed(object: Self.self)))
                        return Disposables.create()
                    }

                    var bag = [Disposable]()
                    let disposable = addIceCandidateAsync(ice: ice)
                            .do(
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to handleCandidate, ", error)
                                    },
                                    onCompleted: { [weak self] in
                                        let peer = self?.connection?.peer ?? "-"
                                        self?.logger.log("Added ICE candidate for:\(peer)")
                                    }
                            )
                            .subscribe(
                                    onCompleted: { [weak self] in
                                        if self == nil {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                        } else {
                                            observer(.completed)
                                        }
                                    },
                                    onError: { [weak self] error in
                                        if self == nil {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                        } else if let error = error
                                                as? GBPeerJsError.WebRtcRemoteIceCandidateErrorReason {
                                            observer(.error(GBPeerJsError.webRtcRemoteCandidateError(reason: error)))
                                        } else {
                                            observer(.error(GBPeerJsError.webRtcRemoteCandidateError(
                                                    reason: .unknownError(error)
                                            )))
                                        }
                                    }
                            )
                    bag.append(disposable)
                    return Disposables.create(bag)
                }
        )
    }
}

extension Negotiator {
    /*startConnection(options: any) {
        if (self.webRtcCommonError.type === ConnectionType.Media && options._stream) {
            self._addTracksToConnection(options._stream, peerConnection)
        }

        // What do we need to do now?
        if (options.originator) {
            if (self.webRtcCommonError.type === ConnectionType.Data) {
                const dataConnection = <DataConnection>(<unknown>self.webRtcCommonError)

                const config: RTCDataChannelInit = { ordered: !!options.reliable }

                const dataChannel = peerConnection.createDataChannel(
                    dataConnection.label,
                    config,
                )
                dataConnection.initialize(dataChannel)
            }

            self._makeOffer()
        } else {
            self.handleSDP("OFFER", options.sdp)
        }
    }*/

    // swiftlint:disable:next function_body_length
    private func doStartConnection(
            stream: RTCMediaStream? = nil,
            originator: Bool = false,
            originatorConstraint: RTCMediaConstraints? = nil,
            data: NegotiatorEntity
    ) -> Completable {
        Completable.create(
                subscribe: { [weak self] observer in
                    guard let self = self else {
                        observer(.error(RxError.disposed(object: Self.self)))
                        return Disposables.create()
                    }

                    var bag = [Disposable]()
                    do {
                        let peerConnection = try self.startPeerConnection(data: data)

                        // Set the webRtcCommonError's PC.
                        self.connection?.setPeerConnection(peerConnection)

                        if self.connection?.type == .media,
                           let stream = stream {
                            self.addTracksToConnection(
                                    stream: stream,
                                    peerConnection: peerConnection
                            )
                        }

                        // What do we need to do now?
                        if originator {
                            /*if connection?.type == .data {
                                const dataConnection = <DataConnection > (<unknown > self.connection)

                                const config: RTCDataChannelInit = {
                                    ordered: !!options.reliable
                                }

                                const dataChannel = peerConnection.createDataChannel(
                                        dataConnection.label,
                                        config,
                                        )
                                dataConnection.initialize(dataChannel)
                            }*/

                            let constraint: RTCMediaConstraints
                            if let originatorConstraint = originatorConstraint {
                                constraint = originatorConstraint
                            } else {
                                constraint = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                            }
                            let disposable = makeOffer(mediaConstraint: constraint)
                                    .subscribe(
                                            onCompleted: { [weak self] in
                                                if self == nil {
                                                    observer(.error(RxError.disposed(object: Self.self)))
                                                } else {
                                                    observer(.completed)
                                                }
                                            },
                                            onError: { [weak self] error in
                                                if self == nil {
                                                    observer(.error(RxError.disposed(object: Self.self)))
                                                } else {
                                                    observer(.error(error))
                                                }
                                            }
                                    )
                            bag.append(disposable)
                        } else {
                            let disposable = handleSDP(type: "OFFER", sdp: "")
                                    .subscribe(
                                            onCompleted: { [weak self] in
                                                if self == nil {
                                                    observer(.error(RxError.disposed(object: Self.self)))
                                                } else {
                                                    observer(.completed)
                                                }
                                            },
                                            onError: { [weak self] error in
                                                if self == nil {
                                                    observer(.error(RxError.disposed(object: Self.self)))
                                                } else {
                                                    observer(.error(error))
                                                }
                                            }
                                    )
                            bag.append(disposable)
                        }
                    } catch {
                        observer(.error(error))
                    }
                    return Disposables.create(bag)
                }
        )
    }

    private func startPeerConnection(
            data: NegotiatorEntity
    ) throws -> RTCPeerConnection {
        logger.log("Creating RTCPeerConnection.")

        guard let peerConnection = data.peerFactory
                .peerConnection(with: data.peerConfig, constraints: data.peerConstraint, delegate: nil) else {
            throw GBPeerJsError.webRtcCommonError(reason: .createPeerConnectionFailed)
        }

        setupListeners(peerConnection: peerConnection)

        return peerConnection
    }

    private func setupListeners(peerConnection: RTCPeerConnection) {
        /*let peerId = webRtcCommonError?.peer
        let connectionId = webRtcCommonError?.connectionId
        let connectionType = webRtcCommonError?.type
        let provider = webRtcCommonError?.provider

        // ICE CANDIDATES.
        logger.log("Listening for ICE candidates.")

        peerConnection.delegate = self
        peerConnection.onicecandidate = (evt) => {
            if (!evt.candidate || !evt.candidate.candidate) return

                    logger.log(`Received ICE candidates for $ {
                peerId
            }:`, evt.candidate)

            provider.socket.send({
                type: ServerMessageType.Candidate,
                payload: {
                    candidate: evt.candidate,
                    type: connectionType,
                    connectionId: connectionId,
                },
                dst: peerId,
            })
        }

        peerConnection.oniceconnectionstatechange = () => {
            switch (peerConnection.iceConnectionState) {
            case "failed":
                logger.log(
                        "iceConnectionState is failed, closing connections to " + peerId,
                        )
                self.webRtcCommonError.emit(
                        "error",
                        new Error("Negotiation of webRtcCommonError to " + peerId + " failed."),
                )
                self.webRtcCommonError.close()
                break
            case "closed":
                logger.log(
                        "iceConnectionState is closed, closing connections to " + peerId,
                        )
                self.webRtcCommonError.emit(
                        "error",
                        new Error("Connection to " + peerId + " closed."),
                )
                self.webRtcCommonError.close()
                break
            case "disconnected":
                logger.log(
                        "iceConnectionState changed to disconnected on the webRtcCommonError with " +
                                peerId,
                        )
                break
            case "completed":
                peerConnection.onicecandidate = util.noop
                break
            }

            self.webRtcCommonError.emit(
                    "iceStateChanged",
                    peerConnection.iceConnectionState,
                    )
        }

        // DATACONNECTION.
        logger.log("Listening for data channel")
        // Fired between offer and answer, so options should already be saved
        // in the options hash.
        peerConnection.ondatachannel = (evt) => {
            logger.log("Received data channel")

            const dataChannel = evt.channel
            const webRtcCommonError = <DataConnection > (
                    provider.getConnection(peerId, connectionId)
            )

            webRtcCommonError.initialize(dataChannel)
        }

        // MEDIACONNECTION.
        logger.log("Listening for remote stream")

        peerConnection.ontrack = (evt) => {
            logger.log("Received remote stream")

            const stream = evt.streams[0]
            const webRtcCommonError = provider.getConnection(peerId, connectionId)

            if (webRtcCommonError.type === ConnectionType.Media) {
                const mediaConnection = <MediaConnection > webRtcCommonError

                self._addStreamToMediaConnection(stream, mediaConnection)
            }
        }*/
    }
}

/*extension Negotiator: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("WebRTC - didChange stateChanged - \(stateChanged) | Called when the SignalingState changed.")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("WebRTC - didAdd stream | Called when media is received on a new stream from remote peer.")

        logger.log("Received remote stream")

        logger.log("add stream \(stream.streamId) to media webRtcCommonError \(connectionId ?? "-")")

        if let track = stream.audioTracks.first {
            track.isEnabled = true
            track.source.volume = 10
            self.stream = stream
            self.track = track
            reconfigureAudio()
        } else {
            logger.log("Weird looking stream")
        }

        logger.log("Receiving stream")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("WebRTC - didRemove stream | Called when a remote peer closes a stream.")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("WebRTC - peerConnectionShouldNegotiate |
 Called when negotiation is needed, for example ICE has restarted.")
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

        logger.log("Received ICE candidates for \(peerId):\(candidate.sdp)")

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
}*/

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
