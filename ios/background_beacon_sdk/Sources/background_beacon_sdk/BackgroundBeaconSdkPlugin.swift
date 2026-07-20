import Flutter
import UIKit

/**
 * iOS entry point — class name must match `pluginClass` in pubspec.yaml.
 *
 * Job: receive channel calls → convert Map ↔ struct → delegate to
 * BeaconMonitor. No CoreLocation logic here (that lives in BeaconMonitor).
 *
 * Relaunch from a region event (app killed): no launchOptions handling
 * needed — GeneratedPluginRegistrant calls register as the engine comes up,
 * so BeaconMonitor exists with its delegate immediately and CL delivers the
 * pending event on its own. Events arriving before Dart starts listening
 * are buffered and flushed in onListen.
 */
public class BackgroundBeaconSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let monitor = BeaconMonitor()
    private let permissions = PermissionManager()

    private var eventSink: FlutterEventSink?

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

    private static let detectTimeoutMs = 3000
    private static let pendingEventLimit = 100
}
