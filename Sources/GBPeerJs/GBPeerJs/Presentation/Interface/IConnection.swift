//
// Created by engineering on 29/6/23.
//

import Foundation
import LiveKitWebRTC

protocol IConnection: AnyObject {
    var peer: String { get }
    var connectionId: String { get }
    var type: ConnectionType { get }
    var provider: IPeer? { get }
    var originator: Bool { get }
    var peerConnection: LKRTCPeerConnection? { get }

    func setPeerConnection(_ peer: LKRTCPeerConnection)
    func unsetPeerConnection()
    func addStream(_ stream: LKRTCMediaStream)
    func emitError(_ error: Error)
    func requestClose()
    func emitIceStateChanged(_ state: RTCIceConnectionState)
    func handleMessage(message: [String: Any])
}
