//
// Created by engineering on 25/6/23.
//

import Foundation
import WebRTC
import RxSwift

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
}

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
        logger.log("add tracks from stream \(stream.streamId) to peer webRtcInitError")

        /*guard (peerConnection.canAddTrack) else {
            logger.error("Your browser does't support RTCPeerConnection#addTrack. Ignored.")
            return
        }*/

        stream.audioTracks.forEach {
            peerConnection.add($0, streamIds: [stream.streamId])
        }
    }

    // swiftlint:disable:next function_body_length
    func makeOffer(
            mediaConstraint: RTCMediaConstraints
    ) -> Completable {
        func createOfferAsync() -> Single<RTCSessionDescription> {
            Single.create { [weak self] observer in
                guard let self = self else {
                    observer(.error(RxError.disposed(object: Self.self)))
                    return Disposables.create()
                }

                if let peerConnection = self.connection?.peerConnection {
                    peerConnection.offer(
                            for: mediaConstraint,
                            completionHandler: { [weak self] description, error in
                                if let error = error {
                                    observer(.error(GBPeerJsMakeOfferErrorReason.createLocalOfferFailed(error)))
                                } else if let description = description {
                                    observer(.success(description))
                                } else {
                                    observer(.error(GBPeerJsMakeOfferErrorReason.createLocalOfferFailed(nil)))
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.unknownPeerConnection))
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
                                if let error = error {
                                    observer(.error(GBPeerJsMakeOfferErrorReason.setLocalDescriptionFailed(error)))
                                } else {
                                    observer(.completed)
                                }
                            }
                    )
                } else {
                    observer(.error(GBPeerJsError.unknownPeerConnection))
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

                    let disposable = createOfferAsync()
                            .do(
                                    onSuccess: { [weak self] _ in
                                        self?.logger.log("Created offer.")
                                    },
                                    onError: { [weak self] error in
                                        self?.logger.log("Failed to createOffer, ", error)
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
                                                        sdp: .init(
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
                                                observer(.error(GBPeerJsError.webRtcMakeOfferError(
                                                        reason: .submitLocalOfferFailed(nil)
                                                )))
                                            }
                                        } catch {
                                            observer(.error(GBPeerJsError.webRtcMakeOfferError(
                                                    reason: .submitLocalOfferFailed(error)
                                            )))
                                        }
                                    },
                                    onError: { [weak self] error in
                                        guard self != nil else {
                                            return
                                        }
                                        if let error = error as? GBPeerJsMakeOfferErrorReason {
                                            observer(.error(GBPeerJsError.webRtcMakeOfferError(reason: error)))
                                        } else {
                                            observer(.error(GBPeerJsError.webRtcMakeOfferError(
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

    func handleSDP(_ sss: String, _ vvv: Any) -> Completable {
        fatalError("not yet implemented")
    }
}

extension Negotiator {
    /*startConnection(options: any) {
        if (self.webRtcInitError.type === ConnectionType.Media && options._stream) {
            self._addTracksToConnection(options._stream, peerConnection)
        }

        // What do we need to do now?
        if (options.originator) {
            if (self.webRtcInitError.type === ConnectionType.Data) {
                const dataConnection = <DataConnection>(<unknown>self.webRtcInitError)

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

                        // Set the webRtcInitError's PC.
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
                                                guard self != nil else {
                                                    return
                                                }
                                                observer(.completed)
                                            },
                                            onError: { [weak self] error in
                                                guard self != nil else {
                                                    return
                                                }
                                                observer(.error(error))
                                            }
                                    )
                            bag.append(disposable)
                        } else {
                            let disposable = handleSDP("OFFER", "")
                                    .subscribe(
                                            onCompleted: { [weak self] in
                                                guard self != nil else {
                                                    return
                                                }
                                                observer(.completed)
                                            },
                                            onError: { [weak self] error in
                                                guard self != nil else {
                                                    return
                                                }
                                                observer(.error(error))
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
            throw GBPeerJsError.webRtcInitError(reason: .createPeerConnectionFailed)
        }

        setupListeners(peerConnection: peerConnection)

        return peerConnection
    }

    private func setupListeners(peerConnection: RTCPeerConnection) {
        /*let peerId = webRtcInitError?.peer
        let connectionId = webRtcInitError?.connectionId
        let connectionType = webRtcInitError?.type
        let provider = webRtcInitError?.provider

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
                self.webRtcInitError.emit(
                        "error",
                        new Error("Negotiation of webRtcInitError to " + peerId + " failed."),
                )
                self.webRtcInitError.close()
                break
            case "closed":
                logger.log(
                        "iceConnectionState is closed, closing connections to " + peerId,
                        )
                self.webRtcInitError.emit(
                        "error",
                        new Error("Connection to " + peerId + " closed."),
                )
                self.webRtcInitError.close()
                break
            case "disconnected":
                logger.log(
                        "iceConnectionState changed to disconnected on the webRtcInitError with " +
                                peerId,
                        )
                break
            case "completed":
                peerConnection.onicecandidate = util.noop
                break
            }

            self.webRtcInitError.emit(
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
            const webRtcInitError = <DataConnection > (
                    provider.getConnection(peerId, connectionId)
            )

            webRtcInitError.initialize(dataChannel)
        }

        // MEDIACONNECTION.
        logger.log("Listening for remote stream")

        peerConnection.ontrack = (evt) => {
            logger.log("Received remote stream")

            const stream = evt.streams[0]
            const webRtcInitError = provider.getConnection(peerId, connectionId)

            if (webRtcInitError.type === ConnectionType.Media) {
                const mediaConnection = <MediaConnection > webRtcInitError

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

        logger.log("add stream \(stream.streamId) to media webRtcInitError \(connectionId ?? "-")")

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
