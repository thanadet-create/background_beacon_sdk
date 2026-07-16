import CoreLocation
import Flutter

/**
 * จัดการ location authorization — beacon บน iOS ใช้สิทธิ์ location ไม่ใช่ bluetooth
 * (CLBeaconRegion อยู่ใต้ CoreLocation ระบบมองการเจอ beacon = การรู้ตำแหน่ง)
 *
 * Flow เดียวกับฝั่ง Android: request เก็บ result ค้าง → ระบบโชว์ dialog →
 * delegate ตอบกลับ → resolve แล้วเคลียร์ / กันเรียกซ้อนด้วย error code เดียวกัน
 *
 * ใช้ CLLocationManager แยกตัวจาก BeaconMonitor ได้ — authorization เป็น
 * state ระดับ app ทุก instance เห็นเหมือนกัน แต่ delegate แยกกันชัดกว่า
 *
 * ขอ Always เพราะ background monitoring ต้องใช้ แต่ iOS 13+ dialog แรกให้
 * user เลือกได้แค่ While-Using (ระบบค่อย prompt ยกระดับเป็น Always ทีหลังเอง)
 * — จึงนับ granted ทั้ง Always และ WhenInUse (WhenInUse = scan ได้เฉพาะ foreground)
 */
final class PermissionManager: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var pendingResult: FlutterResult?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(result: @escaping FlutterResult) {
        // ไม่มี plist key → requestAlwaysAuthorization เงียบหาย ไม่มี dialog
        // ไม่มี callback — pending ค้างตลอดกาล จับให้พังดัง ๆ ตั้งแต่ตรงนี้
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil
        else {
            result(FlutterError(
                code: "PERMISSION_PLIST_MISSING",
                message: "Info.plist must contain NSLocationAlwaysAndWhenInUseUsageDescription",
                details: nil))
            return
        }

        // ตอบ result เดิมซ้ำ = crash — กันเรียกซ้อนตอนมี dialog ค้าง
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
        // notDetermined ยิงมาตอน set delegate ครั้งแรกด้วย — ยังไม่ใช่คำตอบ
        guard status != .notDetermined, let result = pendingResult else { return }
        pendingResult = nil
        result(isGranted(status))
    }

    // iOS 14+
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resolvePending(authStatus())
    }

    // pre-14 (iOS 13) — ระบบเรียกตัวใดตัวหนึ่งตามเวอร์ชัน ไม่ซ้ำกัน
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        resolvePending(status)
    }
}
