//
// Created by engineering on 27/6/23.
//

import Foundation

extension GBPeer {
    struct PeerOptions {
        let debug: Bool
        let host: String?
        let port: Int?
        let path: String?
        let key: String?
        let token: String?
        let secure: Bool
        let pingInterval: TimeInterval?

        init(
                debug: Bool,
                host: String? = nil,
                port: Int? = nil,
                path: String? = nil,
                key: String? = nil,
                token: String? = nil,
                secure: Bool,
                pingInterval: TimeInterval? = nil
        ) {
            self.debug = debug
            self.host = host
            self.port = port
            self.path = path
            self.key = key
            self.token = token
            self.secure = secure
            self.pingInterval = pingInterval
        }
    }
}
