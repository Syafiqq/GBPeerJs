//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC

public struct GBPeerBuilder {
    let peerFactory: RTCPeerConnectionFactory
}

public struct GBPeerConnectionBuilder {
    let peerBuilder: GBPeerBuilder
    let peerConstraint: RTCMediaConstraints
    let peerConfigBuilder: (RTCConfiguration) -> Void
}

public struct GBPeerMediaStream {
    let stream: RTCMediaStream
    let peerBuilder: GBPeerConnectionBuilder
}

public enum GBPeerMedia {
    func getMediaBuilder(
            peerFactoryBuilder: () -> RTCPeerConnectionFactory
    ) -> GBPeerBuilder {
        GBPeerBuilder(peerFactory: peerFactoryBuilder())
    }
}
