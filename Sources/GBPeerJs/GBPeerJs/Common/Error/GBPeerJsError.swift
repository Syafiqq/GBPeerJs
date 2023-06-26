//
// Created by engineering on 26/6/23.
//

import Foundation

public enum GBPeerJsInitializationErrorReason: Error {
    case createPeerConnectionFailed
}

public enum GBPeerJsError: Error {
    case initialization(reason: GBPeerJsInitializationErrorReason)
}
