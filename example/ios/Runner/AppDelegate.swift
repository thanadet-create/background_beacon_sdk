import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // จำเป็นสำหรับโชว์ notification ตอน app อยู่ foreground —
    // ไม่มี delegate = iOS เงียบ banner ทิ้ง (FlutterAppDelegate
    // implement willPresent ให้แล้ว แค่ต้องตั้งตัวเองเป็น delegate)
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // channel ของ Live Activity (โค้ดฝั่ง app — ไม่ใช่ plugin)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityManager") {
      LiveActivityManager.register(with: registrar.messenger())
    }
  }
}
