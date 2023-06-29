//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC

public struct GBPeerBuilder {
    let peerFactory: RTCPeerConnectionFactory

    internal init(peerFactory: RTCPeerConnectionFactory) {
        self.peerFactory = peerFactory
    }
}

public struct GBPeerConnectionBuilder {
    let peerBuilder: GBPeerBuilder
    let peerConstraint: RTCMediaConstraints
    let peerConfigBuilder: (RTCConfiguration) -> Void
}

public struct GBPeerMediaStream {
    let stream: RTCMediaStream
    let peerBuilder: GBPeerConnectionBuilder
    let offerConstraint: RTCMediaConstraints
}

public enum GBPeerMedia {
    func getMediaBuilder(
            peerFactoryBuilder: () -> RTCPeerConnectionFactory
    ) -> GBPeerBuilder {
        GBPeerBuilder(peerFactory: peerFactoryBuilder())
    }
}
