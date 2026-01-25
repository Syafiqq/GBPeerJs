//
// Created by engineering on 29/6/23.
//

import Foundation

struct PeerJsOfferRequestEntity: Encodable {
    let type: String
    let payload: Payload
    let dst: String
}

extension PeerJsOfferRequestEntity {
    struct Payload: Encodable {
        let sdp: SDP
        let type: String
        let connectionId: String
        let browser: String
    }

    struct SDP: Encodable {
        let sdp: String
        let type: String
    }
}
