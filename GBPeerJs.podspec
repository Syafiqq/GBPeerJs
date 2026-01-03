Pod::Spec.new do |s|
  s.name                    = "GBPeerJs"
  s.version                 = "1.4.7"
  s.summary                 = "Summary"
  s.description             = <<-DESC
PeerJs Swift port
                            DESC
  s.homepage                = "https://geniebook.com"
  s.license                 = 'MIT'
  s.author                  = { "Geniebook" => "developer@geniebook.com" }
  s.source                  = { :git => "https://bitbucket.org/beautyfu/ios-gb-peer-js.git", :tag => s.version.to_s }

  s.requires_arc            = true

  s.ios.deployment_target   = '13.0'

  s.source_files            = 'Sources/GBPeerJs/GBPeerJs/**/*.swift'

  s.swift_version = '5.6'

  s.dependency 'WebRTC-SDK', '= 129.6668.01-beta.1'
  s.dependency 'RxSwift', '~> 6'
  s.dependency 'Starscream', '~> 4'
  s.dependency 'LifetimeTracker', '= 1.8.4'
end
