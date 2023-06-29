//
// Created by engineering on 29/6/23.
//

import Foundation

struct PeerJsCandidateRequestEntity: Encodable {
    let type: String
    let payload: Payload
    let dst: String
}

extension PeerJsCandidateRequestEntity {
    struct Payload: Encodable {
        let candidate: Candidate
        let type: String
        let connectionId: String
    }

    struct Candidate: Encodable {
        let candidate: String
        let sdpMLineIndex: Int32
        let sdpMid: String?
    }
}
