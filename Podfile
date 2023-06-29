source 'https://bitbucket.org/beautyfu/ios-pod-specs.git'
source 'https://cdn.cocoapods.org/'

workspace 'GBPeerJs'
# Uncomment the next line to define a global platform for your project

def dev_pods
  pod 'SwiftLint', '~> 0.51'
end

def lib_pods
  pod 'LanguageManager-iOS', '~> 1.2.6-beta.2'
  pod 'GBWebRTC', '= 114.0.5735.124'
end

def lib_test_pods
  pod 'Cuckoo', '~> 1.10'
  pod 'Quick', '~> 6.1'
  pod 'Nimble', '~> 12.0'
end

def example_lib_pods
  pod 'GBPeerJs', :path => './'
end

target 'GBPeerJs' do
  project 'Sources/GBPeerJs/GBPeerJs.xcodeproj'
  platform :ios, '11.2'

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
  platform :ios, '11.2'

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
      case t.name
      when "Cuckoo", "Quick", "Nimble"
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      else
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.2'
      end
    end
  end
end
