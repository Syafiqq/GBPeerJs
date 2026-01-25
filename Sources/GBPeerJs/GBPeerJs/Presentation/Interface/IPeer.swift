//
// Created by engineering on 29/6/23.
//

import Foundation

protocol IPeer: AnyObject {
    var socket: ISocket? { get }

    func getConnection(peerId: String, connectionId: String) -> IConnection?
    func storeMessage(connectionId: String, message: [String: Any])
    func getMessages(connectionId: String) -> [[String: Any]]
    func removeConnection(_ connection: IConnection)
    func emitError(_ error: Error)
}
