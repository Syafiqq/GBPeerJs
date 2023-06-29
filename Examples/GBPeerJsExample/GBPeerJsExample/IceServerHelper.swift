//
// Created by engineering on 29/6/23.
//

import Foundation
import WebRTC

enum IceServerSource {
    case coturn
    case metered
    case meteredStatic
    case xirsys
    case xirsysStatic
    case twillio
}

enum IceServerHelper {
    static func getIceServers(for source: IceServerSource, completion: @escaping ([RTCIceServer]) -> Void) {
        switch source {
        case .coturn: fetchCoturnIceServer(completion: completion)
        case .metered: fetchMeteredIceServer(completion: completion)
        case .meteredStatic: fetchMeteredStaticIceServer(completion: completion)
        case .xirsys: fetchXirsysIceServer(completion: completion)
        case .xirsysStatic: fetchXirsisStaticIceServer(completion: completion)
        case .twillio: fetchTwilioIceServer(completion: completion)
        }
    }

    // swiftlint:disable all

    private static func fetchCoturnIceServer(completion: ([RTCIceServer]) -> Void) {
        let iceServers = [
            RTCIceServer(
                    urlStrings: ["stun:stun.l.google.com:19302"]
            ),
            RTCIceServer(
                    urlStrings: ["turn:stream2.geniebook.com:3478"],
                    username: "coturn-prod",
                    credential: "VO1DGjtUzdxqANjxO27P5o2M1xKOgJd7"
            )
        ]
        completion(iceServers)
    }

    private static func fetchMeteredIceServer(completion: @escaping ([RTCIceServer]) -> Void) {
        struct Ice: Decodable {
            var urls: String?
            var username: String?
            var credential: String?
        }

        let url = URL(string: "https://gbgb.metered.live/api/v1/turn/credentials?apiKey=57661e4964818a06873a6c7a23eda21ca5ed")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let jsonDecoder = JSONDecoder()
            guard let data = data,
                  let ices = try? jsonDecoder.decode([Ice].self, from: data) else {
                completion([])
                return
            }
            let iceServers: [RTCIceServer] = ices.compactMap({
                guard let urls = $0.urls else {
                    return nil
                }
                return RTCIceServer(urlStrings: [urls], username: $0.username, credential: $0.credential, tlsCertPolicy: .insecureNoCheck)
            })
            DispatchQueue.main.async {
                completion(iceServers)
            }
        }

        task.resume()
    }

    private static func fetchMeteredStaticIceServer(completion: @escaping ([RTCIceServer]) -> Void) {
        let iceServers = [
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
        completion(iceServers)
    }

    private static func fetchXirsysIceServer(completion: @escaping ([RTCIceServer]) -> Void) {
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let jsonDecoder = JSONDecoder()
            guard let data = data,
                  let response = try? jsonDecoder.decode(Ice.self, from: data),
                  response.s?.contains("ok") == true,
                  let iceServers = response.v?.iceServers else {
                completion([])
                return
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

            DispatchQueue.main.async {
                completion(stuns + turns)
            }
        }

        task.resume()
    }

    private static func fetchXirsisStaticIceServer(completion: @escaping ([RTCIceServer]) -> Void) {
        let iceServers = [
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
        completion(iceServers)
    }

    private static func fetchTwilioIceServer(completion: @escaping ([RTCIceServer]) -> Void) {
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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let jsonDecoder = JSONDecoder()
            guard let data = data,
                  let response = try? jsonDecoder.decode(Ice.self, from: data),
                  let ices = response.ice_servers else {
                completion([])
                return
            }
            let iceServers: [RTCIceServer] = ices.compactMap({
                guard let urls = $0.urls else {
                    return nil
                }
                return RTCIceServer(urlStrings: [urls], username: $0.username, credential: $0.credential, tlsCertPolicy: .insecureNoCheck)
            })

            DispatchQueue.main.async {
                completion(iceServers)
            }
        }

        task.resume()
    }

    // swiftlint:enable all
}
