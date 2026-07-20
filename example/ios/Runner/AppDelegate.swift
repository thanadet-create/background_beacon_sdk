import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required to show notifications while the app is foregrounded —
    // without a delegate iOS silently drops the banner (FlutterAppDelegate
    // already implements willPresent; we only have to become the delegate)
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Live Activity channel (app-side code — not the plugin)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityManager") {
      LiveActivityManager.register(with: registrar.messenger())
    }
  }
}
