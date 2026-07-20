import CoreLocation

// Models
struct BeaconRegionData {
    let identifier: String
    let uuid: UUID
    let major: CLBeaconMajorValue?
    let minor: CLBeaconMinorValue?

    init?(map: [String: Any?]) {
        guard let identifier = map["identifier"] as? String,
              let uuidString = map["uuid"] as? String,
              let uuid = UUID(uuidString: uuidString)
        else { return nil }
        self.identifier = identifier
        self.uuid = uuid
        self.major = (map["major"] as? NSNumber).map { CLBeaconMajorValue(truncating: $0) }
        self.minor = (map["minor"] as? NSNumber).map { CLBeaconMinorValue(truncating: $0) }
    }

    /// Region for monitoring
    var clRegion: CLBeaconRegion {
        let region: CLBeaconRegion
        if let major, let minor {
            region = CLBeaconRegion(uuid: uuid, major: major, minor: minor, identifier: identifier)
        } else if let major {
            region = CLBeaconRegion(uuid: uuid, major: major, identifier: identifier)
        } else {
            region = CLBeaconRegion(uuid: uuid, identifier: identifier)
        }
        region.notifyEntryStateOnDisplay = true
        return region
    }

    var constraint: CLBeaconIdentityConstraint {
        if let major, let minor {
            return CLBeaconIdentityConstraint(uuid: uuid, major: major, minor: minor)
        }
        if let major {
            return CLBeaconIdentityConstraint(uuid: uuid, major: major)
        }
        return CLBeaconIdentityConstraint(uuid: uuid)
    }

}

struct ScanSettingsData {
    /// duration/notification are Android concerns
    /// (iOS region monitoring is scheduled by the OS itself)
    let rangingEnabled: Bool

    /// Location keep-alive so ranging keeps flowing in the background —
    /// session-scoped: starts on first region enter, stops after leaving
    /// all regions (conditions/costs in the ScanSettings dartdoc).
    let continuousRanging: Bool

    /// Ranged-event flush cadence — matches reportDelay on Android
    /// (CL's didRange fires ~1/s, too often for the "one event per cycle"
    /// contract).
    let scanIntervalMs: Int

    init?(map: [String: Any?]) {
        guard let rangingEnabled = map["rangingEnabled"] as? Bool else { return nil }
        self.rangingEnabled = rangingEnabled
        self.continuousRanging = (map["continuousRanging"] as? Bool) ?? false
        // Dart always sends it (required) — fallback just keeps the struct non-nil
        self.scanIntervalMs = (map["scanIntervalMs"] as? Int) ?? 5000
    }
}

/// CLBeacon → Map per the Dart `Beacon` wire contract.
/// txPower: CoreLocation doesn't expose it → -1 / distance: `accuracy`
/// in meters (-1 = unknown). `mac` is deliberately omitted (iOS never
/// exposes MAC) — Dart reads the missing key as null.
func beaconMap(_ beacon: CLBeacon) -> [String: Any] {
    [
        "uuid": beacon.uuid.uuidString.lowercased(),
        "major": beacon.major.intValue,
        "minor": beacon.minor.intValue,
        "rssi": beacon.rssi,
        "txPower": -1,
        "distance": beacon.accuracy,
        "lastSeen": iso8601(Date()),
    ]
}

/// Map per the Dart `BeaconEvent` wire contract.
/// type must match the enum names exactly: "enterRegion" | "exitRegion" | "ranged"
/// ("monitoringPaused" | "monitoringResumed" exist in the contract but are
/// Android-only — iOS never emits them)
func eventMap(type: String, region: String, beacons: [[String: Any]]) -> [String: Any] {
    [
        "type": type,
        "region": region,
        "beacons": beacons,
        "timestamp": iso8601(Date()),
    ]
}

// Local time without timezone suffix — matches DateTime.parse on Dart and iso8601 on Kotlin
private let iso8601Formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    // POSIX locale guards against device-locale drift (Buddhist calendar / 12-hour)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

func iso8601(_ date: Date) -> String {
    iso8601Formatter.string(from: date)
}
