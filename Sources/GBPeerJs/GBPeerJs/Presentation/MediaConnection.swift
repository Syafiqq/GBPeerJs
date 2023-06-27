//
// Created by engineering on 27/6/23.
//

import Foundation
import WebRTC

class MediaConnection: IConnection {
    private static let idPrefix = "mc_"

    var peer: String
    var connectionId: String
    var type: ConnectionType = .media

    var originator: Bool

    weak var provider: PeerProvider?
    var peerConnection: RTCPeerConnection?

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
    }

    func emitError(_ error: Error) {
    }

    func close() {
    }

    func emitIceStateChanged(_ state: RTCIceConnectionState) {
    }
}

private extension MediaConnection {

}
