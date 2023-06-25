//
// Created by engineering on 25/6/23.
//

import Foundation

protocol Connection: AnyObject {
}

class Negotiator {
    weak var connection: Connection?

    init(connection: Connection?) {
        self.connection = connection
    }
}
