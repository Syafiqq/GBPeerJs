//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC

public struct GBPeerBuilder {
    let peerFactory: RTCPeerConnectionFactory

    // @swiftlint:disable:next unneeded_synthesized_initializer
    internal init(peerFactory: RTCPeerConnectionFactory) {
        self.peerFactory = peerFactory
    }
}

public struct GBPeerConnectionBuilder {
    let peerBuilder: GBPeerBuilder
    let peerConstraint: RTCMediaConstraints
    let peerConfigBuilder: (RTCConfiguration) -> Void

    public init(
            peerBuilder: GBPeerBuilder,
            peerConstraint: RTCMediaConstraints,
            peerConfigBuilder: @escaping (RTCConfiguration) -> Void
    ) {
        self.peerBuilder = peerBuilder
        self.peerConstraint = peerConstraint
        self.peerConfigBuilder = peerConfigBuilder
    }
}

public struct GBPeerMediaStream {
    let stream: RTCMediaStream
    let peerBuilder: GBPeerConnectionBuilder
    let offerConstraint: RTCMediaConstraints

    public init(stream: RTCMediaStream, peerBuilder: GBPeerConnectionBuilder, offerConstraint: RTCMediaConstraints) {
        self.stream = stream
        self.peerBuilder = peerBuilder
        self.offerConstraint = offerConstraint
    }
}

public enum GBPeerMedia {
    public static func getMediaBuilder(
            peerFactoryBuilder: () -> RTCPeerConnectionFactory
    ) -> GBPeerBuilder {
        GBPeerBuilder(peerFactory: peerFactoryBuilder())
    }
}
