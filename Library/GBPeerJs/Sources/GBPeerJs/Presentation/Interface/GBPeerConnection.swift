//
// Created by engineering on 29/6/23.
//

import Foundation
import LiveKitWebRTC

public protocol GBPeerConnection: AnyObject {
    func answer(stream: GBPeerMediaStream)
    func close()
}
