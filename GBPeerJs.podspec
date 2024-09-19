Pod::Spec.new do |s|
  s.name                    = "GBPeerJs"
  s.version                 = "2.0.1"
#  s.peer_js_version         = "1.4.7"
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

  s.dependency 'LanguageManager-iOS', '~> 1.2.6-beta.2'
  s.dependency 'WebRTC-SDK', '= 114.5735.08'
  s.dependency 'RxSwift', '~> 6'
  s.dependency 'Starscream', '~> 4'
end
