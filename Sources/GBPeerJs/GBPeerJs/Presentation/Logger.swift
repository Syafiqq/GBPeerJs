//
// Created by engineering on 22/6/23.
//

import Foundation

protocol ILogger {
    func log(_  messages: Any...)
    func error(_  messages: Any...)
    func warn(_  messages: Any...)
}

class Logger: ILogger {
    var debug: Bool = false

    init() {
    }

    func log(_  messages: Any...) {
        print("PeerJs ", messages)
    }

    func error(_  messages: Any...) {
        log(messages)
    }

    func warn(_  messages: Any...) {
        log(messages)
    }
}
