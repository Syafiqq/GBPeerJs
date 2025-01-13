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
    var peerConnection: RTCPeerConnection? { get }

    func setPeerConnection(_ peer: RTCPeerConnection)
    func unsetPeerConnection()
    func addStream(_ stream: RTCMediaStream)
    func emitError(_ error: Error)
    func requestClose()
    func emitIceStateChanged(_ state: RTCIceConnectionState)
    func handleMessage(message: [String: Any])
}
