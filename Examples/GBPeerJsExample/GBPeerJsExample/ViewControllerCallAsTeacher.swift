//
//  ViewController.swift
//  GBPeerJsExample
//
//  Created by engineering on 29/11/22.
//

import UIKit
import LiveKitWebRTC
import GBPeerJs

class ViewControllerCallAsTeacher: UIViewController {

    let studentId = "101843"
    let onlineLessonId = "22233"
    let meetingRoonmId = "2555000000022233"
    var iceServers: [LKRTCIceServer] = []
    private var peer: GBPeer?
    private var media: GBPeerMediaConnection?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        trackLifetime()
    }

    required init(coder: NSCoder) {
        fatalError("not yet implemented")
    }

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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Quit",
                style: .plain,
                target: self,
                action: #selector(onQuit)
        )
        IceServerHelper.getIceServers(
                for: .meteredStatic,
                completion: { [weak self] iceServers in
                    self?.iceServers = iceServers
                    self?.onMetadataChanged()
                }
        )
    }

    @objc
    func onQuit() {
        dismiss(animated: true)
    }

    private func onMetadataChanged() {
        guard !iceServers.isEmpty else {
            return
        }

        let peer = GBPeer(
                id: "gbt-\(onlineLessonId)",
                options: GBPeer.PeerOptions(
                        debug: true,
                        secure: true
                )
        )
        self.peer = peer
        self.peer?.delegate = self
    }

    func answerStudent(media: GBPeerJs.GBPeerConnection) {
        guard let media = media as? GBPeerMediaConnection else {
            return
        }
        self.media = media
        let peer = "gbt-\(onlineLessonId)"

        let constraint = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let factory = LKRTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
        let peerFactory: GBPeerBuilder = GBPeerMedia.getMediaBuilder(peerFactoryBuilder: { factory })
        let peerBuilder = GBPeerConnectionBuilder(
                peerBuilder: peerFactory,
                peerConstraint: constraint,
                peerConfigBuilder: { [weak self] config in
                    config.iceServers = self?.iceServers ?? []
                    config.sdpSemantics = .unifiedPlan
                }
        )
        let audioSource = factory.audioSource(with: constraint)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.source.volume = 10
        let stream = factory.mediaStream(withStreamId: "audio0")
        stream.addAudioTrack(audioTrack)

        let peerMedia = GBPeerMediaStream(
                stream: stream,
                peerBuilder: peerBuilder,
                offerConstraint: constraint
        )
        do {
            media.answer(stream: peerMedia)
            media.delegate = self
        } catch {
            print("CurrentLog - answer call - \(error)")
        }
    }
}

extension ViewControllerCallAsTeacher: GBPeerDelegate {
    func peerJs(_ sender: GBPeerJs.GBPeer, onOpen withId: String?) {
        print("CurrentLog - peerJs - onOpen - \(withId)")
    }

    func peerJs(_ sender: GBPeerJs.GBPeer, onClose: ()) {
        print("CurrentLog - peerJs - onClose")
    }

    func peerJs(_ sender: GBPeerJs.GBPeer, onDisconnected withId: String?) {
        print("CurrentLog - peerJs - onDisconnected - \(withId)")
    }

    func peerJs(_ sender: GBPeerJs.GBPeer, onError: Error) {
        print("CurrentLog - peerJs - onError - \(onError)")
    }

    func peerJs(_ sender: GBPeerJs.GBPeer, onCall withConnection: GBPeerJs.GBPeerConnection) {
        print("CurrentLog - peerJs - onCall")
        answerStudent(media: withConnection)
    }
}

extension ViewControllerCallAsTeacher: GBPeerMediaConnectionDelegate {
    func mediaConnection(_: GBPeerMediaConnection, onRemoteStreamAdded: LKRTCMediaStream) {
        print("CurrentLog - peerJsMedia - onRemoteStreamAdded")
    }

    func mediaConnection(_: GBPeerMediaConnection, onClose: ()) {
        print("CurrentLog - peerJsMedia - onClose")
    }

    func mediaConnection(_: GBPeerMediaConnection, onError: Error) {
        print("CurrentLog - peerJsMedia - onError - \(onError)")
    }

    func mediaConnection(_: GBPeerMediaConnection, onIceStateChanged: LKRTCIceConnectionState) {
        print("CurrentLog - peerJsMedia - onIceStateChanged - \(onIceStateChanged)")
    }
}

import LifetimeTracker

extension ViewControllerCallAsTeacher: LifetimeTrackable {
    public class var lifetimeConfiguration: LifetimeConfiguration {
        LifetimeConfiguration(maxCount: 1)
    }
}
