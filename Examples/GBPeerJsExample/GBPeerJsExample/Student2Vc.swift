// swiftlint:disable all

//
//  ViewController.swift
//  GBPeerJsExample
//
//  Created by engineering on 29/11/22.
//

import UIKit
import WebRTC
import GBPeerJs

class Student2Vc: UIViewController {

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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }


    @objc
    func onQuit() {
        dismiss(animated: true)
    }

    @objc func fetchCoturnIceServer() {
        iceServers = [

            RTCIceServer(
                    urlStrings: ["stun:stun.l.google.com:19302"]
            ),
            RTCIceServer(
                    urlStrings: ["turn:stream2.geniebook.com:3478"],
                    username: "coturn-prod",
                    credential: "VO1DGjtUzdxqANjxO27P5o2M1xKOgJd7"
            )
        ]
        onMetadataChanged()
    }

    @objc func fetchMeteredIceServer() {
        struct Ice: Decodable {
            var urls: String?
            var username: String?
            var credential: String?
        }

        let url = URL(string: "https://gbgb.metered.live/api/v1/turn/credentials?apiKey=57661e4964818a06873a6c7a23eda21ca5ed")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let jsonDecoder = JSONDecoder()
            guard let data = data,
                  let ices = try? jsonDecoder.decode([Ice].self, from: data) else {
                fatalError("not yet implemented")
            }
            let iceServers: [RTCIceServer] = ices.compactMap({
                guard let urls = $0.urls else {
                    fatalError("not yet implemented")
                }
                return RTCIceServer(urlStrings: [urls], username: $0.username, credential: $0.credential, tlsCertPolicy: .insecureNoCheck)
            })
            DispatchQueue.main.async { [weak self] in
                self?.iceServers = iceServers
                self?.onMetadataChanged()
            }
        }

        task.resume()
    }

    @objc func fetchMeteredStaticIceServer() {
        iceServers = [
            RTCIceServer(
                    urlStrings: ["stun:stun.relay.metered.ca:80"]
            ),
            RTCIceServer(
                    urlStrings: ["turn:a.relay.metered.ca:80"],
                    username: "f6719a28c0c5342e9be05d99",
                    credential: "oep2e6f6Sx1DTW9N"
            ),
            RTCIceServer(
                    urlStrings: ["turn:a.relay.metered.ca:80?transport=tcp"],
                    username: "f6719a28c0c5342e9be05d99",
                    credential: "oep2e6f6Sx1DTW9N"
            ),
            RTCIceServer(
                    urlStrings: ["turn:a.relay.metered.ca:443"],
                    username: "f6719a28c0c5342e9be05d99",
                    credential: "oep2e6f6Sx1DTW9N"
            ),
            RTCIceServer(
                    urlStrings: ["turn:a.relay.metered.ca:443?transport=tcp"],
                    username: "f6719a28c0c5342e9be05d99",
                    credential: "oep2e6f6Sx1DTW9N"
            ),
        ]
        onMetadataChanged()
    }

    @objc func fetchXirsysIceServer() {
        struct Ice: Decodable {
            var s: String?
            var v: IceV?
        }

        struct IceV: Decodable {
            var iceServers: IceServer?
        }

        struct IceServer: Decodable {
            var username: String?
            var credential: String?
            var urls: [String]?
        }

        let username = "Syafiqq"
        let password = "fd8a8d46-1017-11ee-a428-0242ac130002"
        let loginString = String(format: "%@:%@", username, password)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let url = URL(string: "https://global.xirsys.net/_turn/gclass")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["format": "urls"])

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let jsonDecoder = JSONDecoder()
            guard let data = data,
                  let response = try? jsonDecoder.decode(Ice.self, from: data),
                  response.s?.contains("ok") == true,
                  let iceServers = response.v?.iceServers else {
                fatalError("not yet implemented")
            }
            let stuns: [RTCIceServer] = iceServers.urls?
                    .filter({ $0.contains("stun:") })
                    .compactMap {
                        RTCIceServer(urlStrings: [$0], username: iceServers.username, credential: iceServers.credential, tlsCertPolicy: .insecureNoCheck)
                    } ?? []

            let turns: [RTCIceServer] = iceServers.urls?
                    .filter({ $0.contains("turn:") })
                    .compactMap {
                        RTCIceServer(urlStrings: [$0], username: iceServers.username, credential: iceServers.credential, tlsCertPolicy: .insecureNoCheck)
                    } ?? []

            DispatchQueue.main.async { [weak self] in
                self?.iceServers = stuns + turns
                self?.onMetadataChanged()
            }
        }

        task.resume()
    }

    @objc func fetchXirsisStaticIceServer() {
        iceServers = [
            RTCIceServer(
                    urlStrings: ["stun:hk-turn1.xirsys.com"]
            ),
            RTCIceServer(
                    urlStrings: [
                        "turn:hk-turn1.xirsys.com:80?transport=udp",
                        "turn:hk-turn1.xirsys.com:3478?transport=udp",
                        "turn:hk-turn1.xirsys.com:80?transport=tcp",
                        "turn:hk-turn1.xirsys.com:3478?transport=tcp",
                        "turns:hk-turn1.xirsys.com:443?transport=tcp",
                        "turns:hk-turn1.xirsys.com:5349?transport=tcp"
                    ],
                    username: "VB9bb2SYtgOFPbuMxwdMltxF87cbLsO6rny-6881RfME9CG4NaLbHp0I95IZc_8UAAAAAGSUEnlTeWFmaXFx",
                    credential: "18bcb870-10de-11ee-89ed-0242ac120004"
            ),
        ]
        onMetadataChanged()
    }

    @objc func fetchTwilioIceServer() {
        struct Ice: Decodable {
            var ice_servers: [IceServer]?
        }

        struct IceServer: Decodable {
            var username: String?
            var credential: String?
            var urls: String?
        }

        let username = "AC7e395b9b574d6a0430068e690d2cd1b4"
        let password = "ef8963b987589162d83b245abf8560f9"
        let loginString = String(format: "%@:%@", username, password)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(username)/Tokens.json")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let jsonDecoder = JSONDecoder()
            guard let data = data,
                  let response = try? jsonDecoder.decode(Ice.self, from: data),
                  let ices = response.ice_servers else {
                fatalError("not yet implemented")
            }
            let iceServers: [RTCIceServer] = ices.compactMap({
                guard let urls = $0.urls else {
                    fatalError("not yet implemented")
                }
                return RTCIceServer(urlStrings: [urls], username: $0.username, credential: $0.credential, tlsCertPolicy: .insecureNoCheck)
            })

            DispatchQueue.main.async { [weak self] in
                self?.iceServers = iceServers
                self?.onMetadataChanged()
            }
        }

        task.resume()
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
        fetchMeteredStaticIceServer()
    }

    private func onMetadataChanged() {
        guard !iceServers.isEmpty else {
            return
        }
        print("onMetadataChanged")

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

    func doCall(media: GBPeerJs.GBPeerConnection) {
        guard let media = media as? GBPeerMediaConnection else {
            return
        }
        self.media = media
        let peer = "gbt-\(onlineLessonId)"
        let factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
        let peerFactory: GBPeerBuilder = GBPeerMedia.getMediaBuilder(peerFactoryBuilder: { factory })
        let peerBuilder = GBPeerConnectionBuilder(
                peerBuilder: peerFactory,
                peerConstraint: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
                peerConfigBuilder: { [weak self] config in
                    config.iceServers = self?.iceServers ?? []
                    config.sdpSemantics = .unifiedPlan
                    config.disableLinkLocalNetworks = true
                }
        )
        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.source.volume = 10
        let stream = factory.mediaStream(withStreamId: "audio0")
        stream.addAudioTrack(audioTrack)
        let peerMedia = GBPeerMediaStream(
                stream: stream,
                peerBuilder: peerBuilder,
                offerConstraint: RTCMediaConstraints(
                        mandatoryConstraints: [
                            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse
                        ],
                        optionalConstraints: nil
                )
        )
        do {
            media.answer(stream: peerMedia)
            media.delegate = self
        } catch {
            print("CurrentLog - answer call - \(error)")
        }
    }
}

extension Student2Vc: GBPeerDelegate {
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
        doCall(media: withConnection)
    }
}
extension Student2Vc: GBPeerMediaConnectionDelegate {
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

extension Student2Vc: LifetimeTrackable {
    public class var lifetimeConfiguration: LifetimeConfiguration {
        LifetimeConfiguration(maxCount: 1)
    }
}

// swiftlint:enable all
