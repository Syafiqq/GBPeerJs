//
// Created by engineering on 22/6/23.
//

import Foundation

class Logger {
    static let shared = Logger()

    var debug: Bool = false

    init() {
    }

    func log(_  messages: Any...) {
        print("PeerJs ", messages)
    }
}
