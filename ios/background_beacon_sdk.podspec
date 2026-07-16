#
# Podspec ของ plugin ฝั่ง iOS — pod install ของ app อ่านไฟล์นี้
# NOTE: version/author ไว้แก้ตอนจะ publish จริง
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
  # path ตาม SPM layout — CocoaPods กับ SPM ใช้ source ชุดเดียวกัน
  s.source_files     = 'background_beacon_sdk/Sources/background_beacon_sdk/**/*.swift'
  s.dependency 'Flutter'

  # iOS 13 ขั้นต่ำ — ใช้ CLBeaconIdentityConstraint / CLBeaconRegion(uuid:) API ใหม่
  # เลี่ยง API เก่า (proximityUUID) ที่ deprecated ทั้งชุด
  s.platform = :ios, '13.0'

  # Flutter.framework ไม่มี i386 slice — กัน build พังบน simulator เก่า
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
