//
// Created by engineering on 25/6/23.
//

import Foundation
import WebRTC
import RxSwift

class Negotiator: NSObject {
    weak var connection: IConnection?
    private let logger: ILogger = Logger.shared

    init(connection: IConnection) {
        self.connection = connection
        super.init()
    }

    deinit {
        doCleanup()
    }
}

private extension Negotiator {
    /** Returns a PeerConnection object set up correctly (for data, media). */
    func doStartConnection(
            // swiftlint:disable:previous function_body_length
            stream: GBPeerMediaStream? = nil,
            originator: Bool = false,
            mediaOfferConstraint: RTCMediaConstraints,
            remoteOfferSdp: String,
            remoteOfferSdpType: String
    ) -> Completable {
        Completable.create(
                subscribe: { [weak self] observer in
                    guard let self = self else {
                        observer(.error(RxError.disposed(object: Self.self)))
                        return Disposables.create()
                    }

                    var bag = [Disposable]()
                    do {
                        if self.connection?.type == .media,
                           let stream = stream {
                            let peerConnection = try self.startPeerConnection(peerBuilder: stream.peerBuilder)

                            // Set the webRtcCommonError's PC.
                            self.connection?.setPeerConnection(peerConnection)

                            self.addTracksToConnection(
                                    stream: stream.stream,
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

                            let disposable = self.makeOffer(mediaConstraint: mediaOfferConstraint)
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
                            let disposable = self.doHandleSDP(
                                    type: ServerMessageType.offer.rawValue,
                                    sdp: remoteOfferSdp,
                                    sdpType: remoteOfferSdpType,
                                    mediaOfferConstraint: mediaOfferConstraint
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

    /** Start a PC. */
    func startPeerConnection(
            peerBuilder: GBPeerConnectionBuilder
    ) throws -> RTCPeerConnection {
        logger.log("Creating RTCPeerConnection.")

        let config = RTCConfiguration()
        peerBuilder.peerConfigBuilder(config)
        guard let peerConnection = peerBuilder.peerBuilder.peerFactory
                .peerConnection(with: config, constraints: peerBuilder.peerConstraint, delegate: nil) else {
            throw GBPeerJsError.webRtcCommonError(reason: .createPeerConnectionFailed)
        }

        setupListeners(peerConnection: peerConnection)

        return peerConnection
    }

    /** Set up various WebRTC listeners. */
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

        peerConnection.delegate = self
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
                                        self?.logger.log("Created offer.")
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

                                        let request = PeerJsOfferRequestEntity(
                                                type: ServerMessageType.offer.rawValue,
                                                payload: PeerJsOfferRequestEntity.Payload(
                                                        sdp: PeerJsOfferRequestEntity.SDP(
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
                                        self?.logger.log("Created answer.")
                                    },
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to create answer, ", error)
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

                                        let request = PeerJsOfferRequestEntity(
                                                type: ServerMessageType.answer.rawValue,
                                                payload: PeerJsOfferRequestEntity.Payload(
                                                        sdp: PeerJsOfferRequestEntity.SDP(
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

    /** Handle an SDP. */
    func doHandleSDP(
            // swiftlint:disable:previous function_body_length
            type: String,
            sdp: String,
            sdpType: String,
            mediaOfferConstraint: RTCMediaConstraints
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

                    let sdp = RTCSessionDescription(type: RTCSessionDescription.type(for: sdpType), sdp: sdp)
                    self.logger.log("Setting remote description", sdp.sdp)

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
                                        if type == ServerMessageType.offer.rawValue {
                                            return self.makeAnswer(mediaConstraint: mediaOfferConstraint)
                                        }
                                        return Completable.empty()
                                    }
                            )
                            .subscribe(
                                    onCompleted: { [weak self] in
                                        if self == nil {
                                            observer(.error(RxError.disposed(object: Self.self)))
                                            return
                                        } else {
                                            observer(.completed)
                                        }
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

    /** Handle a candidate. */
    func doHandleCandidate(_ ice: RTCIceCandidate) -> Completable {
        // swiftlint:disable:previous function_body_length
        func addIceCandidateAsync(ice: RTCIceCandidate) -> Completable {
            Completable.create(subscribe: { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.add(
                            ice,
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

        logger.log("handleCandidate: ", "ice")

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
        logger.log("add tracks from stream \(stream.streamId) to peer connection")

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
            connection?.requestClose()
        case .closed:
            logger.log("iceConnectionState is closed, closing connections to \(connection?.peer ?? "-")")
            connection?.emitError(GBPeerJsError.webRtcLocalCandidateError(reason: .iceConnectionStateClosed))
            connection?.requestClose()
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
        guard peerConnection.iceConnectionState != .completed,
              !candidate.sdp.isEmpty else {
            return
        }

        logger.log("Received ICE candidates for \(connection?.peer ?? "-"):, \(candidate.sdp)")

        let candidateEntity = PeerJsCandidateRequestEntity(
                type: ServerMessageType.candidate.rawValue,
                payload: PeerJsCandidateRequestEntity.Payload(
                        candidate: PeerJsCandidateRequestEntity.Candidate(
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
