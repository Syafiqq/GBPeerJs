//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC

public protocol GBPeerConnection: AnyObject {
    func answer(stream: GBPeerMediaStream)
    func close()
}
