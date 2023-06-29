# GBPeerJS: Simple peer-to-peer with WebRTC
## Swift port of [peer.js](https://github.com/peers/peerjs)

### https://t.me/joinchat/VWI0UBxnG7f7_DV7

[![Backers on Open Collective](https://opencollective.com/peer/backers/badge.svg)](#backers)
[![Sponsors on Open Collective](https://opencollective.com/peer/sponsors/badge.svg)](#sponsors)

GBPeerJS provides a complete, configurable, and easy-to-use peer-to-peer API built on top of WebRTC, supporting both data channels and media streams.

## Live Example

Here's an example application that uses both media and data connections: https://glitch.com/~peerjs-video. The example also uses its own [PeerServer](https://github.com/peers/peerjs-server).

## Setup

**Include the library**

with npm:
~~npm install peerjs~~

with yarn:
~~yarn add peerjs~~

with pod 
```ruby
source 'https://bitbucket.org/beautyfu/ios-pod-specs.git'

pod GBPeerJS
```

## Usage
~~import { Peer } from "peerjs";~~
```swift
import GBPeerJs
```

**Create a Peer**

```swift
let peer = GBPeer(id: "pick-an-id")
// You can pick your own id or omit the id if you want to get a random one from the server.
```

## ~~Data connections~~ Not yet supported

~~**Connect**~~

```swift
// const conn = peer.connect("another-peers-id");
// conn.on("open", () => {
// 	conn.send("hi!");
// });
```

~~**Receive**~~

```swift
// peer.on("connection", (conn) => {
// 	conn.on("data", (data) => {
// 		// Will print 'hi!'
// 		console.log(data);
// 	});
// 	conn.on("open", () => {
// 		conn.send("hello!");
// 	});
// });
```

## Media calls

**Call**

```swift
let constraint = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

// Create Peer factory
let factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
let peerFactory: GBPeerBuilder = GBPeerMedia.getMediaBuilder(peerFactoryBuilder: { factory })

// Create Peer Builder
let peerBuilder = GBPeerConnectionBuilder(
        peerBuilder: peerFactory,
        peerConstraint: constraint,
        peerConfigBuilder: { [weak self] config in
            config.iceServers = self?.iceServers ?? []
            config.sdpSemantics = .unifiedPlan
        }
)

// Create Video/Audio stream
let audioSource = factory.audioSource(with: constraint)
let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
let mediaStream = factory.mediaStream(withStreamId: "audio0")
mediaStream.addAudioTrack(audioTrack)

// Create UserMedia
let stream = GBPeerMediaStream(
        stream: mediaStream,
        peerBuilder: peerBuilder,
        offerConstraint: constraint
)

// Invoke call
let call = peer.call("another-peers-id", stream)

// Listen events
call.delegate = self

func mediaConnection(_: GBPeerMediaConnection, onRemoteStreamAdded: RTCMediaStream) {
}

func mediaConnection(_: GBPeerMediaConnection, onClose: ()) {
}

func mediaConnection(_: GBPeerMediaConnection, onError: Error) {
}

func mediaConnection(_: GBPeerMediaConnection, onIceStateChanged: RTCIceConnectionState) {
}
```

**Answer**

```swift
peer.delegate = self
func peerJs(_ sender: GBPeerJs.GBPeer, onOpen withId: String?) {
}

func peerJs(_ sender: GBPeerJs.GBPeer, onClose: ()) {
}

func peerJs(_ sender: GBPeerJs.GBPeer, onDisconnected withId: String?) {
}

func peerJs(_ sender: GBPeerJs.GBPeer, onError: Error) {
}

func peerJs(_ sender: GBPeerJs.GBPeer, onCall withConnection: GBPeerJs.GBPeerConnection) {
    guard let call = withConnection as? GBPeerMediaConnection else {
        return
    }

    let constraint = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    // Create Peer factory
    let factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
    let peerFactory: GBPeerBuilder = GBPeerMedia.getMediaBuilder(peerFactoryBuilder: { factory })

    // Create Peer Builder
    let peerBuilder = GBPeerConnectionBuilder(
            peerBuilder: peerFactory,
            peerConstraint: constraint,
            peerConfigBuilder: { [weak self] config in
                config.iceServers = self?.iceServers ?? []
                config.sdpSemantics = .unifiedPlan
            }
    )

    // Create Video/Audio stream
    let audioSource = factory.audioSource(with: constraint)
    let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
    let mediaStream = factory.mediaStream(withStreamId: "audio0")
    mediaStream.addAudioTrack(audioTrack)

    // Create UserMedia
    let stream = GBPeerMediaStream(
            stream: mediaStream,
            peerBuilder: peerBuilder,
            offerConstraint: constraint
    )

    call.answer(stream: stream)
    call.delegate = self
}

func mediaConnection(_: GBPeerMediaConnection, onRemoteStreamAdded: RTCMediaStream) {
}

func mediaConnection(_: GBPeerMediaConnection, onClose: ()) {
}

func mediaConnection(_: GBPeerMediaConnection, onError: Error) {
}

func mediaConnection(_: GBPeerMediaConnection, onIceStateChanged: RTCIceConnectionState) {
}
```

## ~~Running tests~~ Not yet supported

~~npm test~~

## Phone support

| iOS    | iPadOS | Catalyst      |
|--------|--------|---------------|
| > 11.2 | > 11.2 | Not Supported |

## Safari

1. Safari supports only string data when sending via DataConnection. Use JSON serialization type if you want to communicate with Safari. By default, DataConnection uses Binary serialization type.

## FAQ

Q. ~~I have a message `Critical dependency: the request of a dependency is an expression` in browser's console~~

A. ~~The message occurs when you use PeerJS with Webpack. It is not critical! It relates to Parcel https://github.com/parcel-bundler/parcel/issues/2883 We'll resolve it when updated to Parcel V2.~~

Q. When the Data Connection will supported?

A. Dont have plan

## Links

### [Documentation / API Reference](https://peerjs.com/docs/)

### [PeerServer](https://github.com/peers/peerjs-server)

### [Discuss PeerJS on our Telegram Channel](https://t.me/joinchat/ENhPuhTvhm8WlIxTjQf7Og)

### [Changelog](https://github.com/peers/peerjs/blob/master/CHANGELOG.md)

## Contributors

All iOS Geniebook

## Backers

Thank you to all our backers! [[Become a backer](https://opencollective.com/peer#backer)]

## Sponsors

## License

PeerJS is licensed under the [MIT License](https://tldrlegal.com/l/mit).
