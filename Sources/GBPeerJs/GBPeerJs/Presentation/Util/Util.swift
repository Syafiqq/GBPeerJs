//
// Created by engineering on 29/6/23.
//

import Foundation

enum Util {
    static func browser() -> String {
        UIDevice.current.userInterfaceIdiom == .pad
                ? "iPad"
                : UIDevice.current.userInterfaceIdiom == .phone
                ? "iPhone"
                : "iPod"
    }

    static func randomToken(_ length: Int) -> String {
        let randomTokenSeed = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap({ _ in randomTokenSeed.randomElement() }))
    }
}
