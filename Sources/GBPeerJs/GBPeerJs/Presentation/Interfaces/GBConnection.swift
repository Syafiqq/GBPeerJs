//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC

public protocol GBConnection: AnyObject {
    func answer(stream: RTCMediaStream?)
    func close()
}
