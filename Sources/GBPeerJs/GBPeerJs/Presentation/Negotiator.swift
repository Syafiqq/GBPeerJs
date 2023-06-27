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

    static func randomToken(_ length: Int) -> String {
        let randomTokenSeed = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap({ _ in randomTokenSeed.randomElement() }))
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

struct LocalCandidateRequestEntity: Encodable {
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

    func getConnection(peerId: String, connectionId: String) -> IConnection
}

protocol IConnection: AnyObject {
    var peer: String { get }
    var connectionId: String { get }
    var type: ConnectionType { get }
    var provider: PeerProvider? { get }
    var originator: Bool { get }
    var peerConnection: RTCPeerConnection? { get }

    func setPeerConnection(_ peer: RTCPeerConnection)
    func unsetPeerConnection()
    func addStream(_ stream: RTCMediaStream)
    func emitError(_ error: Error)
    func close()
    func emitIceStateChanged(_ state: RTCIceConnectionState)
}

protocol INegotiator: AnyObject {
    func startConnection(
            stream: RTCMediaStream?,
            originator: Bool,
            originatorConstraint: RTCMediaConstraints?,
            data: NegotiatorEntity
    )

    func handleSDP(
            type: String,
            sdp: String,
            answerMediaConstraint: RTCMediaConstraints?
    )

    func handleCandidate(_ ice: IceCandidate)

    func cleanup()
}

class Negotiator: NSObject, INegotiator {
    weak var connection: IConnection?
    private let logger: ILogger

    private var classBag = DisposeBag()

    init(connection: IConnection, logger: ILogger) {
        self.connection = connection
        self.logger = logger
    }

    func startConnection(
            stream: RTCMediaStream? = nil,
            originator: Bool = false,
            originatorConstraint: RTCMediaConstraints? = nil,
            data: NegotiatorEntity
    ) {
        doStartConnection(
                stream: stream,
                originator: originator,
                originatorConstraint: originatorConstraint,
                data: data
        )
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribe(
                        onCompleted: { [weak self] in
                            self?.logger.log("Success Start IConnection")
                        },
                        onError: { [weak self] error in
                            self?.logger.log("Failed to start connection")
                            self?.connection?.emitError(error)
                        }
                )
                .disposed(by: classBag)
    }

    func handleSDP(
            type: String,
            sdp: String,
            answerMediaConstraint: RTCMediaConstraints? = nil
    ) {
        doHandleSDP(
                type: type,
                sdp: sdp,
                answerMediaConstraint: answerMediaConstraint
        )
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribe(
                        onCompleted: { [weak self] in
                            self?.logger.log("Success handle SDP")
                        },
                        onError: { [weak self] error in
                            self?.logger.log("Failed to handle SDP")
                            self?.connection?.emitError(error)
                        }
                )
                .disposed(by: classBag)
    }

    func handleCandidate(_ ice: IceCandidate) {
        doHandleCandidate(ice)
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribeOn(SerialDispatchQueueScheduler(qos: .default))
                .subscribe(
                        onCompleted: { [weak self] in
                            self?.logger.log("Success handle Candidate")
                        },
                        onError: { [weak self] error in
                            self?.logger.log("Failed to handle candidate")
                            self?.connection?.emitError(error)
                        }
                )
                .disposed(by: classBag)
    }

    func cleanup() {
        classBag = DisposeBag()
        doCleanup()
    }

    deinit {
        cleanup()
    }
}

private extension Negotiator {
    // swiftlint:disable:next function_body_length
    func doStartConnection(
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
                            fatalError("not yet implemented")
                            let disposable = doHandleSDP(type: "OFFER", sdp: "")
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

    func startPeerConnection(
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

    func setupListeners(peerConnection: RTCPeerConnection) {
        // ICE CANDIDATES.
        logger.log("Listening for ICE candidates.")
        // peerConnection.onicecandidate
        // peerConnection.oniceconnectionstatechange

        // DATACONNECTION.
        logger.log("Listening for data channel")
        // Fired between offer and answer, so options should already be saved
        // in the options hash.
        // peerConnection.ondatachannel

        // MEDIACONNECTION.
        logger.log("Listening for remote stream")
        // peerConnection.ontrack
    }

    func doCleanup() {
        logger.log("Cleaning up PeerConnection to \(connection?.peer ?? "-")")

        let peerConnection = connection?.peerConnection

        guard peerConnection != nil else {
            return
        }

        connection?.unsetPeerConnection()

        // unsubscribe from all PeerConnection's events
        peerConnection?.delegate = nil

        let peerConnectionNotClosed = peerConnection?.signalingState != .closed
        let dataChannelNotClosed = false

        /*if (self.connection.type === connectiontype.data) {
            const dataconnection = <dataconnection>(<unknown>self.connection)
            const datachannel = dataconnection.datachannel

            if (datachannel) {
                datachannelnotclosed =
                        !!datachannel.readystate && datachannel.readystate !== "closed"
            }
        }*/

        if peerConnectionNotClosed || dataChannelNotClosed {
            peerConnection?.close()
        }
    }

    // swiftlint:disable:next function_body_length
    func makeOffer(mediaConstraint: RTCMediaConstraints) -> Completable {
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

        func setLocalDescriptionAsync(session: RTCSessionDescription) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.setLocalDescription(
                            session,
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
                                        self?.logger.log("Created session.")
                                    },
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to createOffer, ", error)
                                    }
                            )
                            /*.map {
                                // Modify session
                                if self.connection.options.sdpTransform,
                                   typeof self.connection.options.sdpTransform === "function" {
                                    session.sdp =
                                            self.connection.options.sdpTransform(session.sdp) || session.sdp
                                }
                            }*/
                            .flatMap({ session in
                                setLocalDescriptionAsync(session: session)
                                        .do(
                                                onError: { [weak self] error in
                                                    self?.logger.log("Failed to setLocalDescription, ", error)
                                                },
                                                onCompleted: { [weak self] in
                                                    let peer = self?.connection?.peer ?? "-"
                                                    self?.logger.log("Set localDescription:\(session.sdp) for:\(peer)")
                                                }
                                        )
                                        .andThen(Single.just(session))
                            })
                            .subscribe(
                                    onSuccess: { [weak self] (session: RTCSessionDescription) in
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

                                        let request = OfferRequestEntity(
                                                type: ServerMessageType.offer.rawValue,
                                                payload: OfferRequestEntity.Payload(
                                                        sdp: OfferRequestEntity.SDP(
                                                                sdp: session.sdp,
                                                                type: RTCSessionDescription.string(for: session.type)
                                                        ),
                                                        type: self.connection?.type.rawValue ?? "",
                                                        connectionId: self.connection?.connectionId ?? "",
                                                        browser: Util.browser()
                                                ),
                                                dst: self.connection?.peer ?? ""
                                        )

                                        let encoder = JSONEncoder()
                                        do {
                                            let requestData = try encoder.encode(request)
                                            if let result = String(data: requestData, encoding: .utf8) {
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

        func setLocalDescriptionAsync(session: RTCSessionDescription) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.setLocalDescription(
                            session,
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
                                        self?.logger.log("Created session.")
                                    },
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to create session, ", error)
                                    }
                            )
                            /*.map {
                                // Modify session
                                if self.connection.options.sdpTransform,
                                   typeof self.connection.options.sdpTransform === "function" {
                                    session.sdp =
                                            self.connection.options.sdpTransform(session.sdp) || session.sdp
                                }
                            }*/
                            .flatMap({ session in
                                setLocalDescriptionAsync(session: session)
                                        .do(
                                                onError: { [weak self] error in
                                                    self?.logger.log("Failed to setLocalDescription, ", error)
                                                },
                                                onCompleted: { [weak self] in
                                                    let peer = self?.connection?.peer ?? "-"
                                                    self?.logger.log("Set localDescription:\(session.sdp) for:\(peer)")
                                                }
                                        )
                                        .andThen(Single.just(session))
                            })
                            .subscribe(
                                    onSuccess: { [weak self] (session: RTCSessionDescription) in
                                        guard let self = self else {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                            return
                                        }

                                        let request = OfferRequestEntity(
                                                type: ServerMessageType.answer.rawValue,
                                                payload: OfferRequestEntity.Payload(
                                                        sdp: OfferRequestEntity.SDP(
                                                                sdp: session.sdp,
                                                                type: RTCSessionDescription.string(for: session.type)
                                                        ),
                                                        type: self.connection?.type.rawValue ?? "",
                                                        connectionId: self.connection?.connectionId ?? "",
                                                        browser: Util.browser()
                                                ),
                                                dst: self.connection?.peer ?? ""
                                        )

                                        let encoder = JSONEncoder()
                                        do {
                                            let requestData = try encoder.encode(request)
                                            if let result = String(data: requestData, encoding: .utf8) {
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
    func doHandleSDP(
            type: String,
            sdp: String,
            answerMediaConstraint: RTCMediaConstraints? = nil
    ) -> Completable {
        func setRemoteDescriptionAsync(session: RTCSessionDescription) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.setRemoteDescription(
                            session,
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
                    let disposable = setRemoteDescriptionAsync(session: sdp)
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
    func doHandleCandidate(_ ice: IceCandidate) -> Completable {
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

        stream.videoTracks.forEach {
            peerConnection.add($0, streamIds: [stream.streamId])
        }
    }

    func addStreamToMediaConnection(
            stream: RTCMediaStream,
            mediaConnection: IConnection
    ) {
        logger.log("add stream \(stream.streamId) to media connection \(mediaConnection.connectionId)")

        mediaConnection.addStream(stream)
    }
}

extension Negotiator: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        logger.log("Received remote stream")

        guard let peerId = connection?.peer,
              let connectionId = connection?.connectionId,
              let connection = connection?.provider?.getConnection(peerId: peerId, connectionId: connectionId),
              connection.type == .media else {
            return
        }

        addStreamToMediaConnection(stream: stream, mediaConnection: connection)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch peerConnection.iceConnectionState {
        case .failed:
            logger.log("iceConnectionState is failed, closing connections to \(connection?.peer ?? "-")")
            connection?.emitError(GBPeerJsError.webRtcLocalCandidateError(reason: .iceConnectionStateFailed))
            connection?.close()
        case .closed:
            logger.log("iceConnectionState is closed, closing connections to \(connection?.peer ?? "-")")
            connection?.emitError(GBPeerJsError.webRtcLocalCandidateError(reason: .iceConnectionStateClosed))
            connection?.close()
        case .disconnected:
            logger.log("iceConnectionState changed to disconnected on the connection with  \(connection?.peer ?? "-")")
        default:
            break
        }

        connection?.emitIceStateChanged(peerConnection.iceConnectionState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard !candidate.sdp.isEmpty else {
            return
        }

        logger.log("Received ICE candidates for \(connection?.peer ?? "-"):, \(candidate.sdp)")

        let candidateEntity = LocalCandidateRequestEntity(
                type: ServerMessageType.candidate.rawValue,
                payload: LocalCandidateRequestEntity.Payload(
                        candidate: LocalCandidateRequestEntity.Candidate(
                                candidate: candidate.sdp,
                                sdpMLineIndex: candidate.sdpMLineIndex,
                                sdpMid: candidate.sdpMid
                        ),
                        type: connection?.type.rawValue ?? "",
                        connectionId: connection?.connectionId ?? ""
                ),
                dst: connection?.peer ?? ""
        )
        let candidateEncoder = JSONEncoder()
        do {
            let candidateData = try candidateEncoder.encode(candidateEntity)
            if let result = String(data: candidateData, encoding: .utf8) {
                connection?.provider?.socket?.send(result)
            }
        } catch {
            logger.error("Submit local candidate failed")
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.log("Received data channel")

        /*const dataChannel = evt.channel
        const connection = <DataConnection>(
                provider.getConnection(peerId, connectionId)
        )

        connection.initialize(dataChannel)*/
    }
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
