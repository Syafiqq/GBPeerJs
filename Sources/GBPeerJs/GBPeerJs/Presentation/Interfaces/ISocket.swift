//
// Created by engineering on 29/6/23.
//

import Foundation

protocol ISocket: AnyObject {
    var delegate: SocketDelegate? { get set }

    func start(id: String, token: String)
    func close()
    func send(_ message: String)
}
