import CoreLocation
import Flutter

final class PermissionManager: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var pendingResult: FlutterResult?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(result: @escaping FlutterResult) {
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil
        else {
            result(FlutterError(
                code: "PERMISSION_PLIST_MISSING",
                message: "Info.plist must contain NSLocationAlwaysAndWhenInUseUsageDescription",
                details: nil))
            return
        }

        guard pendingResult == nil else {
            result(FlutterError(
                code: "PERMISSION_REQUEST_IN_PROGRESS",
                message: "Another permission request is in progress",
                details: nil))
            return
        }

        let status = authStatus()
        if status == .notDetermined {
            pendingResult = result
            manager.requestAlwaysAuthorization()
        } else {
            result(isGranted(status))
        }
    }

    private func authStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        }
        return CLLocationManager.authorizationStatus()
    }

    private func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }

    private func resolvePending(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined, let result = pendingResult else { return }
        pendingResult = nil
        result(isGranted(status))
    }

    // iOS 14+
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resolvePending(authStatus())
    }

    // pre-14 (iOS 13)
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        resolvePending(status)
    }
}
