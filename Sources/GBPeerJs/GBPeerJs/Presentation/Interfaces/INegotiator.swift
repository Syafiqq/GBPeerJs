//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC
import RxSwift

protocol INegotiator: AnyObject {
    func startConnection(
            stream: RTCMediaStream?,
            originator: Bool,
            originatorConstraint: RTCMediaConstraints?,
            data: NegotiatorEntity,
            remoteOfferSdp: String
    ) -> Completable

    func handleSDP(
            type: String,
            sdp: String,
            answerMediaConstraint: RTCMediaConstraints?
    ) -> Completable

    func handleCandidate(_ ice: RTCIceCandidate) -> Completable

    func cleanup()
}
