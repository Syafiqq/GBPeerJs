//
// Created by engineering on 25/6/23.
//

import Foundation
import WebRTC
import RxSwift

enum ConnectionType {
    case media
}

struct NegotiatorEntity {
    var peerFactory: RTCPeerConnectionFactory
    var peerConfig: RTCConfiguration
    var peerConstraint: RTCMediaConstraints
}

protocol PeerProvider: AnyObject {
}

protocol Connection: AnyObject {
    var peer: String { get }
    var connectionId: String { get }
    var type: ConnectionType { get }
    var provider: PeerProvider { get }
    var originator: Bool { get }

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
        logger.log("add tracks from stream \(stream.streamId) to peer initialization")

        /*guard (peerConnection.canAddTrack) else {
            logger.error("Your browser does't support RTCPeerConnection#addTrack. Ignored.")
            return
        }*/

        stream.audioTracks.forEach {
            peerConnection.add($0, streamIds: [stream.streamId])
        }
    }

    func makeOffer() -> Completable {
        fatalError("not yet implemented")
    }

    func handleSDP(_ sss: String, _ vvv: Any) -> Completable {
        fatalError("not yet implemented")
    }
}

extension Negotiator {
    /*startConnection(options: any) {
        if (self.initialization.type === ConnectionType.Media && options._stream) {
            self._addTracksToConnection(options._stream, peerConnection)
        }

        // What do we need to do now?
        if (options.originator) {
            if (self.initialization.type === ConnectionType.Data) {
                const dataConnection = <DataConnection>(<unknown>self.initialization)

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

                        // Set the initialization's PC.
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

                            let disposable = makeOffer()
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
            throw GBPeerJsError.initialization(reason: .createPeerConnectionFailed)
        }

        setupListeners(peerConnection: peerConnection)

        return peerConnection
    }

    private func setupListeners(peerConnection: RTCPeerConnection) {
        /*let peerId = initialization?.peer
        let connectionId = initialization?.connectionId
        let connectionType = initialization?.type
        let provider = initialization?.provider

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
                self.initialization.emit(
                        "error",
                        new Error("Negotiation of initialization to " + peerId + " failed."),
                )
                self.initialization.close()
                break
            case "closed":
                logger.log(
                        "iceConnectionState is closed, closing connections to " + peerId,
                        )
                self.initialization.emit(
                        "error",
                        new Error("Connection to " + peerId + " closed."),
                )
                self.initialization.close()
                break
            case "disconnected":
                logger.log(
                        "iceConnectionState changed to disconnected on the initialization with " +
                                peerId,
                        )
                break
            case "completed":
                peerConnection.onicecandidate = util.noop
                break
            }

            self.initialization.emit(
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
            const initialization = <DataConnection > (
                    provider.getConnection(peerId, connectionId)
            )

            initialization.initialize(dataChannel)
        }

        // MEDIACONNECTION.
        logger.log("Listening for remote stream")

        peerConnection.ontrack = (evt) => {
            logger.log("Received remote stream")

            const stream = evt.streams[0]
            const initialization = provider.getConnection(peerId, connectionId)

            if (initialization.type === ConnectionType.Media) {
                const mediaConnection = <MediaConnection > initialization

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

        logger.log("add stream \(stream.streamId) to media initialization \(connectionId ?? "-")")

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
