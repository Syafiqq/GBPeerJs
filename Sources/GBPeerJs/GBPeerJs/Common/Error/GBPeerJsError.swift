//
// Created by engineering on 26/6/23.
//

import Foundation

public enum GBPeerJsError: Error {
    case connection(reason: GBPeerJsConnectionErrorReason)
}

public enum GBPeerJsConnectionErrorReason: Error {
    case createPeerConnectionFailed
}
