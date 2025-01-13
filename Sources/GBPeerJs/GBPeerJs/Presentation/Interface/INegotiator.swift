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
            mediaOfferConstraint: LKRTCMediaConstraints,
            remoteOfferSdp: String,
            remoteOfferSdpType: String
    ) -> Completable

    func handleSDP(
            type: String,
            sdp: String,
            sdpType: String,
            mediaOfferConstraint: LKRTCMediaConstraints
    ) -> Completable

    func handleCandidate(_ ice: LKRTCIceCandidate) -> Completable

    func cleanup()
}
