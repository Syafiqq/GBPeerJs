source 'https://bitbucket.org/beautyfu/ios-pod-specs.git'
source 'https://cdn.cocoapods.org/'

workspace 'GBPeerJs'
# Uncomment the next line to define a global platform for your project

def dev_pods
  pod 'SwiftLint', '~> 0.57'
end

def lib_pods
  pod 'LanguageManager-iOS', '~> 1.2.9-beta.1'
  pod 'WebRTC-SDK', '= 125.6422.04'
  pod 'Starscream', '~> 4'
  pod 'RxSwift', '~> 6'
  pod 'LifetimeTracker', '= 1.8.4'
end

def lib_test_pods
  pod 'Cuckoo', '~> 1.10'
  pod 'Quick', '~> 6.1'
  pod 'Nimble', '~> 12.0'
end

def example_lib_pods
  lib_pods
end

target 'GBPeerJs' do
  project 'Sources/GBPeerJs/GBPeerJs.xcodeproj'
  platform :ios, '13.0'

  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for GBPeerJs
  dev_pods

  lib_pods

  target 'GBPeerJsTests' do
    platform :ios, '13.0'

    inherit! :complete
    # Pods for testing

    lib_test_pods
  end
end

target 'GBPeerJsExample' do
  project 'Examples/GBPeerJsExample/GBPeerJsExample.xcodeproj'
  platform :ios, '13.0'

  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for GBPeerJsExample
  example_lib_pods

  target 'GBPeerJsExampleTests' do
    platform :ios, '13.0'

    inherit! :search_paths
    # Pods for testing

    lib_test_pods
  end

  target 'GBPeerJsExampleUITests' do
    # Pods for testing
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
