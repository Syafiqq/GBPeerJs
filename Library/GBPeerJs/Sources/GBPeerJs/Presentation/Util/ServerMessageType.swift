//
// Created by engineering on 29/6/23.
//

import Foundation

enum ServerMessageType: String {
    // @formatter:off
    case heartbeat  = "HEARTBEAT"
    case candidate  = "CANDIDATE"
    case offer      = "OFFER"
    case answer     = "ANSWER"
    case open       = "OPEN" // The connection to the server is open.
    case error      = "ERROR" // Server error.
    case idTaken    = "ID-TAKEN" // The selected ID is taken.
    case invalidKey = "INVALID-KEY" // The given API key cannot be found.
    case leave      = "LEAVE" // Another peer has closed its connection to this peer.
    case expire     = "EXPIRE" // The offer sent to a peer has expired without response.
    // @formatter:on
}
