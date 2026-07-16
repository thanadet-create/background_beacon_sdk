import CoreLocation

/**
 * Core logic ฝั่ง iOS — CLLocationManager + CLBeaconRegion
 *
 * Background strategy (ต่างจาก Android):
 * - region monitoring: OS ทำให้ระดับ hardware ทำงานแม้ app โดน kill แล้วปลุกให้
 *   → ไม่ต้องมี state machine / duty cycle เองแบบฝั่ง Kotlin
 * - ranging: ได้เฉพาะ foreground หรือช่วงสั้น ๆ (~10 วิ) หลังถูกปลุก
 * - เพดาน 20 regions ต่อ app — เช็คก่อน start ไม่งั้น OS fail เงียบ
 *
 * Event mapping:
 * - didDetermineState/didEnter/didExit ทุกทางวิ่งเข้า handleTransition เดียว
 *   แล้ว dedupe ด้วย insideRegions (OS ยิงได้หลาย callback ต่อการข้ามเขตครั้งเดียว)
 * - enterRegion ฝั่ง iOS beacons ว่างเสมอ — monitoring รู้แค่ "เข้าเขต"
 *   รายละเอียดราย beacon ต้องรอ ranging (wire contract อนุญาต list ว่าง)
 *
 * Thread: CL delegate callback มาบน thread ที่สร้าง manager (main) —
 * state ทั้งหมดจึงแตะจาก main เท่านั้น ไม่ต้องมี lock
 */
final class BeaconMonitor: NSObject, CLLocationManagerDelegate {

    /// Plugin ต่อท่อนี้เข้า EventChannel — เรียกบน main thread
    var onEvent: (([String: Any]) -> Void)?

    private let manager = CLLocationManager()

    /// identifier → region ที่ monitor อยู่ (ใช้ map constraint กลับเป็น identifier)
    private var regions: [String: BeaconRegionData] = [:]

    /// identifier → constraint ตัวจริงที่ใช้ start ranging — ต้องเก็บ instance เดิม:
    /// CLBeaconIdentityConstraint เป็น NSObject เทียบกันด้วย identity
    /// สร้างใหม่จาก field เดิมแล้ว stopRanging อาจหาตัว match ไม่เจอ
    private var regionConstraints: [String: CLBeaconIdentityConstraint] = [:]
    private var rangingEnabled = false
    private var keepAliveActive = false
    private var insideRegions: Set<String> = []

    private struct PendingDetect {
        let region: BeaconRegionData
        let constraint: CLBeaconIdentityConstraint
        let callback: (Bool) -> Void
        let timeout: DispatchWorkItem
    }

    private var pendingDetects: [PendingDetect] = []

    override init() {
        super.init()
        // ตั้ง delegate ตั้งแต่เกิด — ตอน OS relaunch app จาก region event
        // (app โดน kill) CL จะส่ง event ค้างมาทันทีที่มี delegate รอรับ
        manager.delegate = self
    }

    enum MonitorError: Error, LocalizedError {
        case tooManyRegions(Int)

        var errorDescription: String? {
            switch self {
            case .tooManyRegions(let count):
                return "iOS allows at most 20 monitored regions (got \(count))"
            }
        }
    }

    func startMonitoring(regions: [BeaconRegionData], settings: ScanSettingsData) throws {
        guard regions.count <= 20 else {
            throw MonitorError.tooManyRegions(regions.count)
        }
        stopMonitoring() // contract ฝั่ง Dart: เรียกซ้ำ = แทนที่ชุดเดิมทั้งหมด

        rangingEnabled = settings.rangingEnabled
        for region in regions {
            self.regions[region.identifier] = region
            regionConstraints[region.identifier] = region.constraint
            let clRegion = region.clRegion
            manager.startMonitoring(for: clRegion)
            // ถ้ายืนอยู่ในเขตอยู่แล้วให้รู้เลย — didEnterRegion ยิงเฉพาะตอน "ข้ามเขต"
            manager.requestState(for: clRegion)
        }

        if settings.rangingEnabled && settings.continuousRanging {
            startKeepAlive()
        }
    }

    func stopMonitoring() {
        // กวาดจาก OS ไม่ใช่จาก dict ตัวเอง — region persist ข้าม launch
        // อาจมีชุดค้างจากรอบก่อน app ตาย (จำกัดเฉพาะ CLBeaconRegion —
        // ไม่แตะ geofence อื่นของ app)
        for case let region as CLBeaconRegion in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        for constraint in manager.rangedBeaconConstraints {
            manager.stopRangingBeacons(satisfying: constraint)
        }
        stopKeepAlive()
        regions.removeAll()
        regionConstraints.removeAll()
        insideRegions.removeAll()
        rangingEnabled = false
    }

    // MARK: - continuous ranging keep-alive

    /// กัน app โดน suspend ด้วย location updates ค้างไว้ — app ตื่นตลอด
    /// ranging จึงไหลต่อตอน background (เทคนิคเดียวกับ app นำทาง)
    ///
    /// ตำแหน่งจริงไม่ได้ใช้ — ตั้ง accuracy หยาบสุด + distanceFilter ไกลสุด
    /// ให้ radio ตำแหน่งทำงานน้อยที่สุด ต้นทุนหลักที่เหลือคือ process ที่ไม่หลับ
    private func startKeepAlive() {
        // allowsBackgroundLocationUpdates โดยไม่มี background mode = crash ทันที
        // เช็คก่อนแล้ว fail เสียงดังแบบไม่พัง (Dart แก้อะไรไม่ได้ — เป็น config ของ app)
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes")
            as? [String], modes.contains("location")
        else {
            NSLog("[background_beacon_sdk] continuousRanging requires "
                + "UIBackgroundModes 'location' in Info.plist — skipped")
            return
        }

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.startUpdatingLocation()
        keepAliveActive = true
    }

    private func stopKeepAlive() {
        guard keepAliveActive else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        keepAliveActive = false
    }

    /// one-shot: ranging constraint ชั่วคราวจนเจอหรือครบ timeout — callback บน main
    func detectBeacon(
        region: BeaconRegionData,
        timeoutMs: Int,
        callback: @escaping (Bool) -> Void
    ) {
        let constraint = region.constraint
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDetects.removeAll { $0.region.identifier == region.identifier }
            self.stopRangingIfUnused(constraint)
            callback(false)
        }
        pendingDetects.append(PendingDetect(
            region: region, constraint: constraint, callback: callback, timeout: timeout))

        // startRanging ซ้ำ constraint ที่ range อยู่แล้ว = no-op ปลอดภัย
        manager.startRangingBeacons(satisfying: constraint)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(timeoutMs), execute: timeout)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard let beaconRegion = region as? CLBeaconRegion else { return }
        // .unknown = ยังตัดสินไม่ได้ — อย่าตีความเป็น exit
        guard state != .unknown else { return }
        handleTransition(identifier: beaconRegion.identifier, inside: state == .inside)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion else { return }
        handleTransition(identifier: beaconRegion.identifier, inside: true)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion else { return }
        handleTransition(identifier: beaconRegion.identifier, inside: false)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying constraint: CLBeaconIdentityConstraint
    ) {
        resolveDetects(with: beacons)

        guard rangingEnabled, !beacons.isEmpty else { return }
        guard let identifier = identifier(for: constraint) else { return }
        onEvent?(eventMap(
            type: "ranged",
            region: identifier,
            beacons: beacons.map(beaconMap)))
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        // fail หลัง start ไปแล้ว — ไม่มี result ให้ตอบกลับ Dart ได้ log ไว้พอ
        NSLog("[background_beacon_sdk] monitoring failed for %@: %@",
              region?.identifier ?? "?", error.localizedDescription)
    }

    // MARK: - internals

    private func handleTransition(identifier: String, inside: Bool) {
        guard let region = regions[identifier] else { return }

        if inside {
            // dedupe: didEnterRegion + didDetermineState(.inside) มาคู่กันได้
            guard !insideRegions.contains(identifier) else { return }
            insideRegions.insert(identifier)
            onEvent?(eventMap(type: "enterRegion", region: identifier, beacons: []))
            if rangingEnabled, let constraint = regionConstraints[identifier] {
                manager.startRangingBeacons(satisfying: constraint)
            }
        } else {
            guard insideRegions.remove(identifier) != nil else { return }
            onEvent?(eventMap(type: "exitRegion", region: identifier, beacons: []))
            if let constraint = regionConstraints[identifier] {
                stopRangingIfUnused(constraint)
            }
        }
    }

    /// เทียบ constraint ด้วยค่า field — `==` ของ NSObject เป็น identity ใช้ไม่ได้
    private func sameConstraint(
        _ a: CLBeaconIdentityConstraint,
        _ b: CLBeaconIdentityConstraint
    ) -> Bool {
        a.uuid == b.uuid && a.major == b.major && a.minor == b.minor
    }

    private func identifier(for constraint: CLBeaconIdentityConstraint) -> String? {
        regionConstraints.first { sameConstraint($0.value, constraint) }?.key
    }

    private func resolveDetects(with beacons: [CLBeacon]) {
        guard !pendingDetects.isEmpty, !beacons.isEmpty else { return }
        let resolved = pendingDetects.filter { pending in
            beacons.contains { pending.region.matches($0) }
        }
        guard !resolved.isEmpty else { return }
        pendingDetects.removeAll { pending in
            resolved.contains { $0.region.identifier == pending.region.identifier }
        }
        for pending in resolved {
            pending.timeout.cancel()
            stopRangingIfUnused(pending.constraint)
            pending.callback(true)
        }
    }

    /// หยุด ranging constraint นี้เฉพาะเมื่อไม่มี monitoring/detect อื่นใช้ร่วมอยู่
    private func stopRangingIfUnused(_ constraint: CLBeaconIdentityConstraint) {
        let usedByMonitoring = rangingEnabled && insideRegions.contains { identifier in
            guard let active = regionConstraints[identifier] else { return false }
            return sameConstraint(active, constraint)
        }
        let usedByDetect = pendingDetects.contains { sameConstraint($0.constraint, constraint) }
        if !usedByMonitoring && !usedByDetect {
            manager.stopRangingBeacons(satisfying: constraint)
        }
    }
}
