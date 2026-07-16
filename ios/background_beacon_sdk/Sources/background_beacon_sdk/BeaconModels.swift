import CoreLocation

// Models ฝั่ง Swift ที่ mirror ฝั่ง Dart
// wire contract (ชื่อ key / format) ดู dartdoc ใน lib/src/models/ เป็น spec

struct BeaconRegionData {
    let identifier: String
    let uuid: UUID
    let major: CLBeaconMajorValue?
    let minor: CLBeaconMinorValue?

    init?(map: [String: Any?]) {
        guard let identifier = map["identifier"] as? String,
              let uuidString = map["uuid"] as? String,
              let uuid = UUID(uuidString: uuidString) // case-insensitive อยู่แล้ว
        else { return nil }
        self.identifier = identifier
        self.uuid = uuid
        self.major = (map["major"] as? NSNumber).map { CLBeaconMajorValue(truncating: $0) }
        self.minor = (map["minor"] as? NSNumber).map { CLBeaconMinorValue(truncating: $0) }
    }

    /// Region สำหรับ monitoring — OS persist ให้ข้าม app launch
    var clRegion: CLBeaconRegion {
        let region: CLBeaconRegion
        if let major, let minor {
            region = CLBeaconRegion(uuid: uuid, major: major, minor: minor, identifier: identifier)
        } else if let major {
            region = CLBeaconRegion(uuid: uuid, major: major, identifier: identifier)
        } else {
            region = CLBeaconRegion(uuid: uuid, identifier: identifier)
        }
        // จอสว่างให้ระบบเช็ค state ทันที — enter/exit ไวขึ้นโดยไม่ต้อง ranging
        region.notifyEntryStateOnDisplay = true
        return region
    }

    /// Constraint สำหรับ ranging (คนละ object กับ region แต่ field ชุดเดียวกัน)
    var constraint: CLBeaconIdentityConstraint {
        if let major, let minor {
            return CLBeaconIdentityConstraint(uuid: uuid, major: major, minor: minor)
        }
        if let major {
            return CLBeaconIdentityConstraint(uuid: uuid, major: major)
        }
        return CLBeaconIdentityConstraint(uuid: uuid)
    }

    /// major/minor เป็น nil = wildcard จับทุกค่า (semantics เดียวกับฝั่ง Android)
    func matches(_ beacon: CLBeacon) -> Bool {
        beacon.uuid == uuid &&
            (major == nil || beacon.major.uint16Value == major) &&
            (minor == nil || beacon.minor.uint16Value == minor)
    }
}

struct ScanSettingsData {
    /// interval/duration/notification เป็นเรื่องของ Android
    /// (region monitoring ของ iOS ระบบจัดตารางเอง)
    let rangingEnabled: Bool

    /// เปิด location keep-alive ให้ ranging ไหลต่อตอน background
    /// (ดูเงื่อนไข/ราคาใน dartdoc ของ ScanSettings)
    let continuousRanging: Bool

    init?(map: [String: Any?]) {
        guard let rangingEnabled = map["rangingEnabled"] as? Bool else { return nil }
        self.rangingEnabled = rangingEnabled
        self.continuousRanging = (map["continuousRanging"] as? Bool) ?? false
    }
}

/// CLBeacon → Map ตาม wire contract ของ `Beacon` ฝั่ง Dart
/// txPower: CoreLocation ไม่เปิดเผย → -1 / distance: `accuracy` เป็นเมตร (-1 = ไม่รู้)
/// `mac` จงใจไม่ส่ง (iOS ไม่เปิดเผย MAC) — Dart อ่าน key ที่หายเป็น null เอง
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

/// Map ตาม wire contract ของ `BeaconEvent` ฝั่ง Dart
/// type ต้องตรงชื่อ enum เป๊ะ: "enterRegion" | "exitRegion" | "ranged"
func eventMap(type: String, region: String, beacons: [[String: Any]]) -> [String: Any] {
    [
        "type": type,
        "region": region,
        "beacons": beacons,
        "timestamp": iso8601(Date()),
    ]
}

// local time ไม่มี timezone suffix — ตรงกับ DateTime.parse ฝั่ง Dart และ iso8601 ฝั่ง Kotlin
private let iso8601Formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    // POSIX locale กัน format เพี้ยนตาม locale เครื่อง (ปฏิทินพุทธ/12-hour)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

func iso8601(_ date: Date) -> String {
    iso8601Formatter.string(from: date)
}
