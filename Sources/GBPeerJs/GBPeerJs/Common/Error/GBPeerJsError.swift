//
// Created by engineering on 26/6/23.
//

import Foundation

public enum GBPeerJsInitializationErrorReason: Error {
    case createPeerConnectionFailed
}

public enum GBPeerJsMakeOfferErrorReason: Error {
    case createLocalOfferFailed(Error?)
    case setLocalDescriptionFailed(Error?)
    case submitLocalOfferFailed(Error?)
    case unknownError(Error?)
}

public enum GBPeerJsError: Error {
    case webRtcInitError(reason: GBPeerJsInitializationErrorReason)
    case webRtcMakeOfferError(reason: GBPeerJsMakeOfferErrorReason)
    case unknownPeerConnection
}
