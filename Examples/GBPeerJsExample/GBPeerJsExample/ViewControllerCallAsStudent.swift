//
//  ViewController.swift
//  GBPeerJsExample
//
//  Created by engineering on 29/11/22.
//

import UIKit
import WebRTC
import GBPeerJs

class ViewControllerCallAsStudent: UIViewController {

    let studentId = "101843"
    let onlineLessonId = "22233"
    let meetingRoonmId = "2555000000022233"
    var iceServers: [RTCIceServer] = []
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
                id: "GBS-\(onlineLessonId)-STUDENT-\(studentId)-\(Int64(Date().timeIntervalSince1970 * 1000))",
                options: GBPeer.PeerOptions(
                        debug: true,
                        secure: true
                )
        )
        self.peer = peer
        self.peer?.delegate = self

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.callTeacher()
        }
    }

    func callTeacher() {
        let peer = "gbt-\(onlineLessonId)"

        let constraint = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
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
            let media = try self.peer?.call(
                    peerId: peer,
                    stream: peerMedia
            )
            self.media = media
            media?.delegate = self
        } catch {
            print("CurrentLog - error call - \(error)")
        }
    }
}

extension ViewControllerCallAsStudent: GBPeerDelegate {
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
    }
}

extension ViewControllerCallAsStudent: GBPeerMediaConnectionDelegate {
    func mediaConnection(_: GBPeerMediaConnection, onRemoteStreamAdded: RTCMediaStream) {
        print("CurrentLog - peerJsMedia - onRemoteStreamAdded")
    }

    func mediaConnection(_: GBPeerMediaConnection, onClose: ()) {
        print("CurrentLog - peerJsMedia - onClose")
    }

    func mediaConnection(_: GBPeerMediaConnection, onError: Error) {
        print("CurrentLog - peerJsMedia - onError - \(onError)")
    }

    func mediaConnection(_: GBPeerMediaConnection, onIceStateChanged: RTCIceConnectionState) {
        print("CurrentLog - peerJsMedia - onIceStateChanged - \(onIceStateChanged)")
    }
}

import LifetimeTracker

extension ViewControllerCallAsStudent: LifetimeTrackable {
    public class var lifetimeConfiguration: LifetimeConfiguration {
        LifetimeConfiguration(maxCount: 1)
    }
}
