//
// Created by engineering on 29/6/23.
//

import Foundation
import LiveKitWebRTC
import RxSwift

protocol INegotiator: AnyObject {
    func startConnection(
            stream: GBPeerMediaStream?,
            originator: Bool,
            mediaOfferConstraint: RTCMediaConstraints,
            remoteOfferSdp: String,
            remoteOfferSdpType: String
    ) -> Completable

    func handleSDP(
            type: String,
            sdp: String,
            sdpType: String,
            mediaOfferConstraint: RTCMediaConstraints
    ) -> Completable

    func handleCandidate(_ ice: RTCIceCandidate) -> Completable

    func cleanup()
}
