//
// Created by engineering on 22/6/23.
//

import Foundation

protocol ILogger {
    var debug: Bool { get set }

    func log(_  messages: Any...)
    func error(_  messages: Any...)
    func warn(_  messages: Any...)
}

class Logger: ILogger {
    static let shared = Logger()

    var debug: Bool = false

    init() {
    }

    func log(_  messages: Any...) {
        guard debug else {
            return
        }
        print("PeerJs ", messages)
    }

    func error(_  messages: Any...) {
        log(messages)
    }

    func warn(_  messages: Any...) {
        log(messages)
    }
}
