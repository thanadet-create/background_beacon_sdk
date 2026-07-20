import ActivityKit
import Flutter
import Foundation

/// Live Activity payload — **must be redeclared in the widget extension
/// with the exact same type + field names** (ActivityKit matches across
/// processes by type name and encoded data shape)
struct BeaconActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var beaconCount: Int
        /// Drives the toggle button label on the card (iOS 17+) —
        /// true = show the stop button
        var isScanning: Bool
    }

    var title: String
}

/// MethodChannel → ActivityKit bridge — app-side code (not the SDK):
/// presentation is the app's concern, like local notifications.
/// Dart calls: start / update with {text, count, scanning} — no end:
/// the card stays up and expires on the system's terms (user swipe /
/// ~8 h cap). Return path: card button → ToggleScanIntent →
/// NotificationCenter → invokeMethod("toggle") → Dart decides stop/start
class LiveActivityManager: NSObject {
    static let channelName = "background_beacon_sdk_example/live_activity"

    private static var channel: FlutterMethodChannel?
    private static var toggleObserver: NSObjectProtocol?

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler(handle)
        self.channel = channel

        // Limitation: button tapped while the app is killed — the system
        // launches the process to run the intent, but Dart may not have set
        // its handler yet → that toggle is lost (the normal app-alive case
        // always works)
        toggleObserver = NotificationCenter.default.addObserver(
            forName: .beaconToggleScan, object: nil, queue: .main
        ) { _ in
            self.channel?.invokeMethod("toggle", arguments: nil)
        }
    }

    private static func handle(
        _ call: FlutterMethodCall, result: @escaping FlutterResult
    ) {
        // 16.2: the ActivityContent-style API — anything lower counts as
        // unsupported (16.0 has no Live Activity at all, 16.1's old API is
        // deprecated)
        guard #available(iOS 16.2, *) else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Live Activities require iOS 16.2+",
                details: nil))
            return
        }

        let args = call.arguments as? [String: Any] ?? [:]
        let text = args["text"] as? String ?? ""
        let count = args["count"] as? Int ?? 0
        let scanning = args["scanning"] as? Bool ?? true

        switch call.method {
        case "start":
            start(text: text, count: count, scanning: scanning)
            result(nil)
        case "update":
            update(text: text, count: count, scanning: scanning)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.2, *)
    private static func start(text: String, count: Int, scanning: Bool) {
        // The user can disable this app's Live Activities in Settings —
        // stay silent, no error
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // An existing card (e.g. repeated start) = update instead, so
        // multiple cards never stack
        guard Activity<BeaconActivityAttributes>.activities.isEmpty else {
            update(text: text, count: count, scanning: scanning)
            return
        }

        let attributes = BeaconActivityAttributes(title: "Beacon monitoring")
        let state = BeaconActivityAttributes.ContentState(
            statusText: text, beaconCount: count, isScanning: scanning)
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil))
    }

    @available(iOS 16.2, *)
    private static func update(text: String, count: Int, scanning: Bool) {
        let state = BeaconActivityAttributes.ContentState(
            statusText: text, beaconCount: count, isScanning: scanning)
        Task {
            for activity in Activity<BeaconActivityAttributes>.activities {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

}