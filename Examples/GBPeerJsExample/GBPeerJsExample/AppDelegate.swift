//
//  AppDelegate.swift
//  GBPeerJsExample
//
//  Created by engineering on 29/11/22.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    // MARK: - AppDelegate Lifecycle

    func application(
            _ application: UIApplication,
            willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
            // swiftlint:disable:previous discouraged_optional_collection
    ) -> Bool {
        true
    }

    func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
            // swiftlint:disable:previous discouraged_optional_collection
    ) -> Bool {
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }
}
