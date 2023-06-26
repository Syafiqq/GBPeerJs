//
// Created by engineering on 25/6/23.
//

import Foundation
import WebRTC

enum ConnectionType {
    case media
}


protocol PeerProvider: AnyObject {
}

protocol Connection: AnyObject {
    var peer: String { get }
    var connectionId: String { get }
    var type: ConnectionType { get }
    var provider: PeerProvider { get }
}

class Negotiator: NSObject {
    weak var connection: Connection?
    let logger: ILogger

    init(connection: Connection, logger: ILogger) {
        self.connection = connection
        self.logger = logger
    }

    func startConnection(data: NegotiatorEntity) throws {
        try doStartConnection(data: data)
    }
}

struct NegotiatorEntity {
    var peerFactory: RTCPeerConnectionFactory
    var peerConfig: RTCConfiguration
    var peerConstraint: RTCMediaConstraints
}

extension Negotiator {
    /*startConnection(options: any) {
        const peerConnection = self._startPeerConnection()

        // Set the connection's PC.
        self.connection.peerConnection = peerConnection

        if (self.connection.type === ConnectionType.Media && options._stream) {
            self._addTracksToConnection(options._stream, peerConnection)
        }

        // What do we need to do now?
        if (options.originator) {
            if (self.connection.type === ConnectionType.Data) {
                const dataConnection = <DataConnection>(<unknown>self.connection)

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

    private func doStartConnection(
            data: NegotiatorEntity
    ) throws {
        let peerConnection = try startPeerConnection(data: data)
    }

    private func startPeerConnection(
            data: NegotiatorEntity
    ) throws -> RTCPeerConnection {
        logger.log("Creating RTCPeerConnection.")

        guard let peerConnection = data.peerFactory
                .peerConnection(with: data.peerConfig, constraints: data.peerConstraint, delegate: nil) else {
            throw GBPeerJsError.connection(reason: .createPeerConnectionFailed)
        }

        setupListeners(peerConnection: peerConnection)

        return peerConnection
    }

    private func setupListeners(peerConnection: RTCPeerConnection) {
        /*let peerId = connection?.peer
        let connectionId = connection?.connectionId
        let connectionType = connection?.type
        let provider = connection?.provider

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
                self.connection.emit(
                        "error",
                        new Error("Negotiation of connection to " + peerId + " failed."),
                )
                self.connection.close()
                break
            case "closed":
                logger.log(
                        "iceConnectionState is closed, closing connections to " + peerId,
                        )
                self.connection.emit(
                        "error",
                        new Error("Connection to " + peerId + " closed."),
                )
                self.connection.close()
                break
            case "disconnected":
                logger.log(
                        "iceConnectionState changed to disconnected on the connection with " +
                                peerId,
                        )
                break
            case "completed":
                peerConnection.onicecandidate = util.noop
                break
            }

            self.connection.emit(
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
            const connection = <DataConnection > (
                    provider.getConnection(peerId, connectionId)
            )

            connection.initialize(dataChannel)
        }

        // MEDIACONNECTION.
        logger.log("Listening for remote stream")

        peerConnection.ontrack = (evt) => {
            logger.log("Received remote stream")

            const stream = evt.streams[0]
            const connection = provider.getConnection(peerId, connectionId)

            if (connection.type === ConnectionType.Media) {
                const mediaConnection = <MediaConnection > connection

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

        logger.log("add stream \(stream.streamId) to media connection \(connectionId ?? "-")")

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
