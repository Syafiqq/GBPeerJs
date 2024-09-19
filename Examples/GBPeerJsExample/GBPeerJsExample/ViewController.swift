//
//  ViewController.swift
//  GBPeerJsExample
//
//  Created by engineering on 29/11/22.
//

import UIKit

class ViewController: UIViewController {
    // swiftlint:disable:next unneeded_override
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    // swiftlint:disable:next unneeded_override
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .white
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.presentVc()
        }
    }

    private func presentVc() {
        let vc = ViewControllerCallAsStudent()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
