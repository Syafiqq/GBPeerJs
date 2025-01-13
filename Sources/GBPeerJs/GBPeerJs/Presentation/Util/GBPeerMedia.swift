//
// Created by engineering on 29/6/23.
//

import Foundation
import LiveKitWebRTC

public struct GBPeerBuilder {
    let peerFactory: LKRTCPeerConnectionFactory

    // swiftlint:disable:next unneeded_synthesized_initializer
    internal init(peerFactory: LKRTCPeerConnectionFactory) {
        self.peerFactory = peerFactory
    }
}

public struct GBPeerConnectionBuilder {
    let peerBuilder: GBPeerBuilder
    let peerConstraint: LKRTCMediaConstraints
    let peerConfigBuilder: (LKRTCConfiguration) -> Void

    public init(
            peerBuilder: GBPeerBuilder,
            peerConstraint: LKRTCMediaConstraints,
            peerConfigBuilder: @escaping (LKRTCConfiguration) -> Void
    ) {
        self.peerBuilder = peerBuilder
        self.peerConstraint = peerConstraint
        self.peerConfigBuilder = peerConfigBuilder
    }
}

public struct GBPeerMediaStream {
    let stream: LKRTCMediaStream
    let peerBuilder: GBPeerConnectionBuilder
    let offerConstraint: LKRTCMediaConstraints

    public init(
        stream: LKRTCMediaStream,
        peerBuilder: GBPeerConnectionBuilder,
        offerConstraint: LKRTCMediaConstraints
    ) {
        self.stream = stream
        self.peerBuilder = peerBuilder
        self.offerConstraint = offerConstraint
    }
}

public enum GBPeerMedia {
    public static func getMediaBuilder(
            peerFactoryBuilder: () -> LKRTCPeerConnectionFactory
    ) -> GBPeerBuilder {
        GBPeerBuilder(peerFactory: peerFactoryBuilder())
    }
}
