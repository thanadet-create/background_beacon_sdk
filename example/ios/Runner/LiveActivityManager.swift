import ActivityKit
import Flutter
import Foundation

/// ข้อมูลของ Live Activity — **ต้องประกาศซ้ำใน widget extension ด้วย
/// ชื่อ type + ชื่อ field ตรงกันเป๊ะ** (ActivityKit จับคู่ข้าม process
/// ผ่านชื่อ type และรูปร่างข้อมูลที่ encode)
struct BeaconActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var beaconCount: Int
    }

    var title: String
}

/// สะพาน MethodChannel → ActivityKit — โค้ดฝั่ง app (ไม่ใช่ SDK):
/// การแสดงผลเป็นเรื่องของ app เหมือน local notification
/// Dart เรียก: start / update พร้อม {text, count} — ไม่มี end:
/// การ์ดอยู่ตลอด ปล่อยให้หายตามระบบ (user ปัดทิ้ง / เพดาน ~8 ชม.)
class LiveActivityManager: NSObject {
    static let channelName = "background_beacon_sdk_example/live_activity"

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler(handle)
    }

    private static func handle(
        _ call: FlutterMethodCall, result: @escaping FlutterResult
    ) {
        // 16.2: API แบบ ActivityContent — ต่ำกว่านั้นถือว่าไม่รองรับไปเลย
        // (16.0 ไม่มี Live Activity อยู่แล้ว, 16.1 API เก่า deprecated)
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

        switch call.method {
        case "start":
            start(text: text, count: count)
            result(nil)
        case "update":
            update(text: text, count: count)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.2, *)
    private static func start(text: String, count: Int) {
        // user ปิด Live Activities ของ app ใน Settings ได้ — เงียบ ไม่ error
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // มีตัวเดิมค้าง (เช่น start ซ้ำ) = update แทน กันซ้อนหลายกล่อง
        guard Activity<BeaconActivityAttributes>.activities.isEmpty else {
            update(text: text, count: count)
            return
        }

        let attributes = BeaconActivityAttributes(title: "Beacon monitoring")
        let state = BeaconActivityAttributes.ContentState(
            statusText: text, beaconCount: count)
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil))
    }

    @available(iOS 16.2, *)
    private static func update(text: String, count: Int) {
        let state = BeaconActivityAttributes.ContentState(
            statusText: text, beaconCount: count)
        Task {
            for activity in Activity<BeaconActivityAttributes>.activities {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

}
