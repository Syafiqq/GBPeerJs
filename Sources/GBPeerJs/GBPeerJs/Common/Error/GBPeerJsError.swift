//
// Created by engineering on 26/6/23.
//

import Foundation

public protocol IGBPeerJsError: Error {
    var message: String { get }
}

public enum GBPeerJsError: IGBPeerJsError {
    case webRtcCommonError(reason: WebRtcCommonErrorReason)
    case webRtcLocalOfferError(reason: WebRtcLocalOfferErrorReason)
    case webRtcRemoteOfferError(reason: WebRtcRemoteOfferErrorReason)
    case webRtcLocalAnswerError(reason: WebRtcLocalAnswerErrorReason)
    case webRtcRemoteCandidateError(reason: WebRtcRemoteIceCandidateErrorReason)
    case webRtcLocalCandidateError(reason: WebRtcLocalIceCandidateErrorReason)
    case peerError(reason: PeerErrorReason)

    public var message: String {
        switch self {
        case .webRtcCommonError(let reason): return "PeerError: \(reason.message)"
        case .webRtcLocalOfferError(let reason): return "PeerError: \(reason.message)"
        case .webRtcRemoteOfferError(let reason): return "PeerError: \(reason.message)"
        case .webRtcLocalAnswerError(let reason): return "PeerError: \(reason.message)"
        case .webRtcRemoteCandidateError(let reason): return "PeerError: \(reason.message)"
        case .webRtcLocalCandidateError(let reason): return "PeerError: \(reason.message)"
        case .peerError(let reason): return "PeerError: \(reason.message)"
        }
    }
}

public extension GBPeerJsError {
    enum WebRtcCommonErrorReason: IGBPeerJsError {
        case createPeerConnectionFailed
        case unknownPeerConnection

        public var message: String {
            switch self {
            case .createPeerConnectionFailed: return "Init peer failed"
            case .unknownPeerConnection: return "Init peer error"
            }
        }
    }

    enum WebRtcLocalOfferErrorReason: IGBPeerJsError {
        case createLocalOfferFailed(Error?)
        case setLocalDescriptionFailed(Error?)
        case submitLocalOfferFailed(Error?)
        case unknownError(Error?)

        public var message: String {
            switch self {
            case .createLocalOfferFailed(let error): return "Init local peer failed: \(error?.peerMessage ?? "-")"
            case .setLocalDescriptionFailed(let error): return "Set local peer failed: \(error?.peerMessage ?? "-")"
            case .submitLocalOfferFailed(let error): return "Submit local peer failed: \(error?.peerMessage ?? "-")"
            case .unknownError(let error): return "Set local peer error: \(error?.peerMessage ?? "-")"
            }
        }
    }

    enum WebRtcRemoteOfferErrorReason: IGBPeerJsError {
        case setRemoteDescriptionFailed(Error?)
        case unknownError(Error?)

        public var message: String {
            switch self {
            case .setRemoteDescriptionFailed(let error): return "Setup remote peer failed: \(error?.peerMessage ?? "-")"
            case .unknownError(let error): return "Setup remote error: \(error?.peerMessage ?? "-")"
            }
        }
    }

    enum WebRtcLocalAnswerErrorReason: IGBPeerJsError {
        case createLocalAnswerFailed(Error?)
        case setLocalDescriptionFailed(Error?)
        case submitLocalAnswerFailed(Error?)
        case unknownError(Error?)

        public var message: String {
            switch self {
            case .createLocalAnswerFailed(let error): return "Init answer peer failed: \(error?.peerMessage ?? "-")"
            case .setLocalDescriptionFailed(let error): return "Set answer peer failed: \(error?.peerMessage ?? "-")"
            case .submitLocalAnswerFailed(let error): return "Submit answer peer failed: \(error?.peerMessage ?? "-")"
            case .unknownError(let error): return "Set answer peer error: \(error?.peerMessage ?? "-")"
            }
        }
    }

    enum WebRtcRemoteIceCandidateErrorReason: IGBPeerJsError {
        case setCandidateFailed(Error?)
        case unknownError(Error?)

        public var message: String {
            switch self {
            case .setCandidateFailed(let error): return "Set candidate failed: \(error?.peerMessage ?? "-")"
            case .unknownError(let error): return "Set candidate error: \(error?.peerMessage ?? "-")"
            }
        }
    }

    enum WebRtcLocalIceCandidateErrorReason: IGBPeerJsError {
        case iceConnectionStateFailed
        case iceConnectionStateClosed

        public var message: String {
            switch self {
            case .iceConnectionStateFailed: return "IceConnection failed, closing connection"
            case .iceConnectionStateClosed: return "IceConnection closed, closing connection"
            }
        }
    }

    enum PeerErrorReason: IGBPeerJsError {
        case disconnectAlready
        case stillConnected
        case connectPeerOnDisconnectServer
        case peerAborted
        case unknownError(String)

        public var message: String {
            switch self {
            case .disconnectAlready: return "This peer cannot reconnect to the server. It has already been destroyed"
            case .stillConnected: return "Cannot connect/reconnect because it is not disconnected from the server"
            case .connectPeerOnDisconnectServer: return "Cannot connect to peer, establish a new peer connection"
            case .peerAborted: return "Peer aborted"
            case .unknownError(let message): return "Peer error: \(message)"
            }
        }
    }
}

private extension Error {
    var peerMessage: String? {
        (self as? IGBPeerJsError)?.message
    }
}
