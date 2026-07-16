import Flutter
import UIKit

/**
 * Entry point ฝั่ง iOS — ชื่อ class ต้องตรง `pluginClass` ใน pubspec.yaml
 *
 * หน้าที่: รับ channel call → แปลง Map ↔ struct → delegate ไป BeaconMonitor
 * ห้ามมี CoreLocation logic ที่นี่ (อยู่ BeaconMonitor)
 *
 * Relaunch จาก region event (app โดน kill): ไม่ต้อง handle launchOptions เอง —
 * GeneratedPluginRegistrant เรียก register ตอน engine ขึ้น → BeaconMonitor
 * ถูกสร้างพร้อม delegate ทันที CL จะส่ง event ค้างมาให้เอง
 * event ที่มาก่อน Dart เริ่ม listen ถูก buffer ไว้ flush ตอน onListen
 */
public class BackgroundBeaconSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let monitor = BeaconMonitor()
    private let permissions = PermissionManager()

    private var eventSink: FlutterEventSink?

    /// Event ที่เกิดก่อน Dart listen (ช่วง relaunch) — กันหายช่วง race
    private var pendingEvents: [[String: Any]] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BackgroundBeaconSdkPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "background_beacon_sdk/methods",
            binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(
            name: "background_beacon_sdk/events",
            binaryMessenger: registrar.messenger())

        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    override init() {
        super.init()
        monitor.onEvent = { [weak self] event in
            self?.send(event)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "detectMobileServices":
            result("ios")

        case "requestPermissions":
            permissions.request(result: result)

        case "startMonitoring":
            startMonitoring(call, result: result)

        case "stopMonitoring":
            monitor.stopMonitoring()
            result(nil)

        case "detectBeacon":
            guard let args = call.arguments as? [String: Any?],
                  let region = BeaconRegionData(map: args)
            else {
                result(FlutterError(
                    code: "DETECT_FAILED", message: "Invalid region", details: nil))
                return
            }
            monitor.detectBeacon(region: region, timeoutMs: Self.detectTimeoutMs) { found in
                result(found)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startMonitoring(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any?],
              let regionMaps = args["regions"] as? [[String: Any?]],
              let settingsMap = args["settings"] as? [String: Any?],
              let settings = ScanSettingsData(map: settingsMap)
        else {
            result(FlutterError(
                code: "START_FAILED", message: "Invalid arguments", details: nil))
            return
        }

        // wildcard (uuid == null) ใช้ได้เฉพาะ Android — iOS บังคับรู้ UUID ล่วงหน้า
        // (CLBeaconRegion ไม่มีทางสร้างโดยไม่มี UUID) แจ้ง error ตรง ๆ
        // ดีกว่าปล่อยหลุดไปเป็น "Invalid region"
        guard !regionMaps.contains(where: { !($0["uuid"] is String) }) else {
            result(FlutterError(
                code: "START_FAILED",
                message: "Wildcard region (uuid == null) is not supported on iOS — "
                    + "CLBeaconRegion requires a known UUID",
                details: nil))
            return
        }

        let regions = regionMaps.compactMap(BeaconRegionData.init(map:))
        guard regions.count == regionMaps.count else {
            result(FlutterError(
                code: "START_FAILED", message: "Invalid region in list", details: nil))
            return
        }

        do {
            try monitor.startMonitoring(regions: regions, settings: settings)
            result(nil)
        } catch {
            result(FlutterError(
                code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func send(_ event: [String: Any]) {
        guard let sink = eventSink else {
            pendingEvents.append(event)
            // กัน buffer โตไม่หยุดถ้า Dart ไม่ listen เลย — ทิ้งตัวเก่าสุด
            if pendingEvents.count > Self.pendingEventLimit {
                pendingEvents.removeFirst()
            }
            return
        }
        sink(event)
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        pendingEvents.forEach(events)
        pendingEvents.removeAll()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private static let detectTimeoutMs = 3000 // ตรงกับ DETECT_TIMEOUT_MS ฝั่ง Android
    private static let pendingEventLimit = 100
}
