//
// Created by engineering on 26/6/23.
//

import Foundation

public enum GBPeerJsError: Error {
    case webRtcCommonError(reason: WebRtcCommonErrorReason)
    case webRtcLocalOfferError(reason: WebRtcLocalOfferErrorReason)
    case webRtcRemoteOfferError(reason: WebRtcRemoteOfferErrorReason)
    case webRtcLocalAnswerError(reason: WebRtcLocalAnswerErrorReason)
    case webRtcRemoteCandidateError(reason: WebRtcRemoteIceCandidateErrorReason)
    case webRtcLocalCandidateError(reason: WebRtcLocalIceCandidateErrorReason)
    case peerError(reason: PeerErrorReason)
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

    enum WebRtcLocalAnswerErrorReason: Error {
        case createLocalAnswerFailed(Error?)
        case setLocalDescriptionFailed(Error?)
        case submitLocalAnswerFailed(Error?)
        case unknownError(Error?)
    }

    enum WebRtcRemoteIceCandidateErrorReason: Error {
        case setCandidateFailed(Error?)
        case unknownError(Error?)
    }

    enum WebRtcLocalIceCandidateErrorReason: Error {
        case iceConnectionStateFailed
        case iceConnectionStateClosed
    }

    enum PeerErrorReason: Error {
        case disconnectAlready
        case stillConnected
        case connectPeerOnDisconnectServer
        case connectPeerWithoutMedia
    }
}
