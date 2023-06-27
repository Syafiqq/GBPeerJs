//
// Created by engineering on 27/6/23.
//

import Foundation

public class GBPeer {
}

extension GBPeer: IPeer {
    var socket: ISocket? {
        fatalError("socket has not been implemented")
    }

    func getConnection(peerId: String, connectionId: String) -> IConnection {
        fatalError("getConnection(peerId:connectionId:) has not been implemented")
    }

    func getMessage(connectionId: String) -> [[String: Any]] {
        fatalError("getMessage(connectionId:) has not been implemented")
    }

    func removeConnection(_ connection: IConnection) {
    }
}
