#
# Podspec for the iOS side of the plugin — read by the app's pod install
# NOTE: fix version/author before actually publishing
#
Pod::Spec.new do |s|
  s.name             = 'background_beacon_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Flutter SDK for detecting BLE beacons in background.'
  s.description      = <<-DESC
Flutter SDK for detecting BLE beacons in background on iOS, Android (GMS) and Huawei (HMS) devices.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Path follows the SPM layout — CocoaPods and SPM share one source set
  s.source_files     = 'background_beacon_sdk/Sources/background_beacon_sdk/**/*.swift'
  s.dependency 'Flutter'

  # iOS 13 minimum — uses the modern CLBeaconIdentityConstraint /
  # CLBeaconRegion(uuid:) APIs, avoiding the fully-deprecated proximityUUID set
  s.platform = :ios, '13.0'

  # Flutter.framework has no i386 slice — keeps old-simulator builds from breaking
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
