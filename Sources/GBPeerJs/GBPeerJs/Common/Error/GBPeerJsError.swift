//
// Created by engineering on 26/6/23.
//

import Foundation

public enum GBPeerJsError: Error {
    case webRtcCommonError(reason: WebRtcCommonErrorReason)
    case webRtcLocalOfferError(reason: WebRtcLocalOfferErrorReason)
}

public extension GBPeerJsError {
    enum WebRtcCommonErrorReason: Error {
        case createPeerConnectionFailed
        case unknownPeerConnection
    }

    enum WebRtcLocalOfferErrorReason: Error {
        case createLocalOfferFailed(Error?)
        case setLocalDescriptionFailed(Error?)
        case submitLocalOfferFailed(Error?)
        case unknownError(Error?)
    }

    enum WebRtcRemoteOfferErrorReason: Error {
        case setRemoteDescriptionFailed(Error?)
        case unknownError(Error?)
    }
}
