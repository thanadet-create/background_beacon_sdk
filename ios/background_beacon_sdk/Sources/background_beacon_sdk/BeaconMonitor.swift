import CoreLocation

final class BeaconMonitor: NSObject, CLLocationManagerDelegate {

    var onEvent: (([String: Any]) -> Void)?

    private let manager = CLLocationManager()

    /// identifier
    private var regions: [String: BeaconRegionData] = [:]

    private var regionConstraints: [String: CLBeaconIdentityConstraint] = [:]
    private var rangingEnabled = false
    private var continuousRanging = false
    private var keepAliveActive = false
    private var insideRegions: Set<String> = []

    private var cycleSightings: [String: (region: String, beacon: [String: Any])] = [:]
    private var flushTimer: Timer?

    override init() {
        super.init()
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
        stopMonitoring()

        rangingEnabled = settings.rangingEnabled
        continuousRanging = settings.continuousRanging
        for region in regions {
            self.regions[region.identifier] = region
            regionConstraints[region.identifier] = region.constraint
            let clRegion = region.clRegion
            manager.startMonitoring(for: clRegion)
            manager.requestState(for: clRegion)
        }

        if settings.rangingEnabled {
            startFlushTimer(intervalMs: settings.scanIntervalMs)
        }
    }

    func stopMonitoring() {
        for case let region as CLBeaconRegion in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        for constraint in manager.rangedBeaconConstraints {
            manager.stopRangingBeacons(satisfying: constraint)
        }
        stopKeepAlive()
        stopFlushTimer()
        regions.removeAll()
        regionConstraints.removeAll()
        insideRegions.removeAll()
        rangingEnabled = false
        continuousRanging = false
    }

    // MARK: - ranged aggregation
    private func flushRanged() {
        guard !cycleSightings.isEmpty else { return }
        var byRegion: [String: [[String: Any]]] = [:]
        for entry in cycleSightings.values {
            byRegion[entry.region, default: []].append(entry.beacon)
        }
        cycleSightings.removeAll()
        for (region, beacons) in byRegion {
            onEvent?(eventMap(type: "ranged", region: region, beacons: beacons))
        }
    }

    private func startFlushTimer(intervalMs: Int) {
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(intervalMs) / 1000, repeats: true
        ) { [weak self] _ in
            self?.flushRanged()
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
        cycleSightings.removeAll()
    }

    // MARK: - continuous ranging keep-alive
    private func startKeepAlive() {
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

    // MARK: - CLLocationManagerDelegate
    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard let beaconRegion = region as? CLBeaconRegion else { return }
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
        guard rangingEnabled, !beacons.isEmpty else { return }
        guard let identifier = identifier(for: constraint) else { return }
        for beacon in beacons {
            let key = "\(beacon.uuid.uuidString)/\(beacon.major)/\(beacon.minor)"
            cycleSightings[key] = (region: identifier, beacon: beaconMap(beacon))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        NSLog("[background_beacon_sdk] monitoring failed for %@: %@",
              region?.identifier ?? "?", error.localizedDescription)
    }

    // MARK: - internals
    private func handleTransition(identifier: String, inside: Bool) {
        guard let region = regions[identifier] else { return }

        if inside {
            guard !insideRegions.contains(identifier) else { return }
            insideRegions.insert(identifier)
            onEvent?(eventMap(type: "enterRegion", region: identifier, beacons: []))
            if rangingEnabled, let constraint = regionConstraints[identifier] {
                manager.startRangingBeacons(satisfying: constraint)
            }
            if rangingEnabled && continuousRanging && !keepAliveActive {
                startKeepAlive()
            }
        } else {
            guard insideRegions.remove(identifier) != nil else { return }
            onEvent?(eventMap(type: "exitRegion", region: identifier, beacons: []))
            if let constraint = regionConstraints[identifier] {
                stopRangingIfUnused(constraint)
            }
            if insideRegions.isEmpty {
                stopKeepAlive()
            }
        }
    }

    private func sameConstraint(
        _ a: CLBeaconIdentityConstraint,
        _ b: CLBeaconIdentityConstraint
    ) -> Bool {
        a.uuid == b.uuid && a.major == b.major && a.minor == b.minor
    }

    private func identifier(for constraint: CLBeaconIdentityConstraint) -> String? {
        regionConstraints.first { sameConstraint($0.value, constraint) }?.key
    }

    private func stopRangingIfUnused(_ constraint: CLBeaconIdentityConstraint) {
        let usedByMonitoring = rangingEnabled && insideRegions.contains { identifier in
            guard let active = regionConstraints[identifier] else { return false }
            return sameConstraint(active, constraint)
        }
        if !usedByMonitoring {
            manager.stopRangingBeacons(satisfying: constraint)
        }
    }
}
