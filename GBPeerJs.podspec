Pod::Spec.new do |s|
  s.name                    = "GBPeerJs"
  s.version                 = "0.0.1"
  s.summary                 = "Summary"
  s.description             = <<-DESC
Description
                            DESC
  s.homepage                = "https://geniebook.com"
  s.license                 = 'MIT'
  s.author                  = { "" => "" }
  s.source                  = { :git => "", :tag => s.version.to_s }

  s.requires_arc            = true

  s.ios.deployment_target   = '11.2'

  s.source_files            = 'Sources/GBPeerJs/GBPeerJs/**/*.swift'

  s.swift_version = '5.6'

  s.dependency 'LanguageManager-iOS', '~> 1.2.6-beta.2'
  s.dependency 'GBWebRTC', '= 114.0.5735.124'
  s.dependency 'RxSwift', '~> 5'
end
