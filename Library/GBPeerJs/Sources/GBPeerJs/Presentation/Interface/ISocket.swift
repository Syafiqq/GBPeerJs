//
// Created by engineering on 29/6/23.
//

import Foundation

protocol SocketDelegate: AnyObject {
    func socketJs(onDisconnected: ())
    func socketJs(onNewMessage: [String: Any])
    func socketJs(onNewMessage: Data)
    func socketJs(onError: Error?)
}

protocol ISocket: AnyObject {
    var delegate: SocketDelegate? { get set }

    func start(id: String, token: String)
    func close()
    func send(_ message: String)
}
