# background_beacon_sdk

Flutter plugin สำหรับรับสัญญาณ BLE beacon (iBeacon) ขณะ background — รองรับ
iOS / Android (GMS) / Huawei (HMS) โดย SDK detect platform เองอัตโนมัติ
app เรียกผ่าน `BeaconManager` ตัวเดียวได้ทุก platform

| Platform | กลไก background | ข้อจำกัดหลัก |
|---|---|---|
| iOS | CLBeaconRegion monitoring — OS ปลุก app แม้โดน kill | ranging ต่อเนื่องต้องเปิด `continuousRanging`, จำกัด 20 regions |
| Android (GMS) | PendingIntent scan (แนะนำ) หรือ foreground service | foreground service ต้องมี notification ค้าง |
| Huawei (HMS) | เหมือน Android (BLE ไม่พึ่ง GMS) | user ต้อง whitelist battery optimization ไม่งั้น EMUI ฆ่าทุกกลไก |

## ติดตั้ง

package นี้ไม่ได้ publish ขึ้น pub.dev (`publish_to: none`) — อ้างผ่าน path
หรือ git ใน `pubspec.yaml` ของแอป:

```yaml
dependencies:
  background_beacon_sdk:
    path: ../background_beacon_sdk   # หรือ git: {url: ...}
```

## Setup ต่อ platform

### iOS

`ios/Runner/Info.plist` ต้องมี:

- `NSLocationAlwaysAndWhenInUseUsageDescription` (และ
  `NSLocationWhenInUseUsageDescription`)
- `UIBackgroundModes`: `location`, `bluetooth-central`

อยากเห็น ad notification ตอน app อยู่ foreground ด้วย: ตั้ง
`UNUserNotificationCenter.current().delegate` ใน AppDelegate (ดู `example/`)

### Android

- permission ทั้งหมด SDK ประกาศใน manifest ให้แล้ว — แอปแค่เรียก
  `requestPermissions()` ซึ่งขอครบสองจังหวะ (foreground ก่อน แล้วต่อด้วย
  `ACCESS_BACKGROUND_LOCATION`)
- API 30+ ระบบพาไปหน้า Settings — user ต้องเลือก **"Allow all the time"** เอง
  ไม่งั้นผล scan หยุดทันทีที่ app ลง background
- API 33+ ถ้าใช้โหมด foreground service หรือ `BeaconAds` ควรขอ
  `POST_NOTIFICATIONS` ด้วย ไม่งั้น notification ไม่โชว์

### Huawei

- แนะนำให้พา user ไป whitelist battery optimization
  (Settings → Battery → App launch) ไม่งั้นระบบฆ่า background scan
- ถ้าใช้ HMS Location Kit เพิ่ม: ต้องมี Huawei maven repo + agconnect config

### เครื่อง dev ที่ system locale เป็นไทย

Gradle จะพังที่ `mergeDebugJavaResource` (ปฏิทินพุทธปี 2569 เกินเพดาน zip
date format) — เติมใน `android/gradle.properties` ของแอป:

```
org.gradle.jvmargs=-Duser.language=en -Duser.country=US <flags เดิม...>
```

## Quick start

```dart
import 'package:background_beacon_sdk/background_beacon_sdk.dart';

final manager = BeaconManager();

await manager.initialize();            // detect platform — throw ถ้าไม่รองรับ
await manager.requestPermissions();

manager.onBeaconEvent.listen((event) {
  // event.type: enterRegion / ranged / exitRegion
  for (final beacon in event.beacons) {
    print('${beacon.uuid} ${beacon.major}/${beacon.minor} ${beacon.distance}m');
  }
});

await manager.startMonitoring(
  [BeaconRegion(identifier: 'fleet', uuid: 'e2c56db5-...')],
  ScanSettings(
    scanIntervalMs: 5000,
    scanDurationMs: 2000,
    foregroundServiceNotification: false, // Android: PendingIntent scan (แนะนำ)
    beaconLayout: 'iBeacon',
    rangingEnabled: true,
  ),
);
```

- iOS ต้องเรียก `startMonitoring` ใหม่ทุก launch (OS relaunch app ตอนเข้าเขต
  beacon แม้โดน kill — event ก่อน Dart พร้อมถูก buffer ไว้ให้)
- `BeaconRegion` ไม่ระบุ `uuid` = wildcard จับ iBeacon ทุกตัว —
  **Android เท่านั้น** (iOS ปฏิเสธตอน start เพราะ CLBeaconRegion บังคับรู้
  UUID ล่วงหน้า) → บน iOS ดึงรายชื่อ UUID จาก backend มาสร้าง region แทน
  (เพดาน 20 regions)

## `ScanSettings`

| field | ความหมาย |
|---|---|
| `scanIntervalMs` | จังหวะ `ranged` event — หนึ่ง event ต่อ region ต่อรอบ ทั้งสอง platform |
| `scanDurationMs` | Android โหมด foreground service: ระยะ scan ต่อรอบ duty cycle |
| `foregroundServiceNotification` | Android: `false` = PendingIntent scan (ประหยัดแบต รอด process kill — แนะนำ) / `true` = foreground service + notification ค้าง |
| `rangingEnabled` | เปิด `ranged` event |
| `continuousRanging` | iOS: keep-alive ให้ ranging ไหลต่อเนื่องระหว่างอยู่ในเขต (เริ่มตอน enter หยุดตอน exit ครบทุกเขต) — เปลืองแบตขึ้น ใช้เมื่อต้องยิง analytics/ads ตลอด session |

## Android: รับ event แม้ app โดน kill (headless callback)

เฉพาะโหมด PendingIntent (`foregroundServiceNotification: false`):

```dart
@pragma('vm:entry-point')            // กัน AOT tree-shake
void onBgEvent(BeaconEvent event) {  // ต้องเป็น top-level / static
  // รันใน background isolate — ไม่มี UI/BuildContext
}

await manager.registerBackgroundCallback(onBgEvent); // ก่อน startMonitoring
```

ข้อควรรู้:

- iOS ไม่ต้องใช้กลไกนี้ (OS relaunch app ทั้งตัว) — เรียกได้ เป็น no-op
- rebuild app แล้ว callback handle เก่าใช้ไม่ได้ — ต้องเปิด app แล้ว
  register ใหม่
- reboot เครื่อง: SDK re-register scan ให้อัตโนมัติ
- งานใน callback ที่ยิง HTTP ต้องตั้ง timeout สั้นกว่า ~10 วิ
  (เพดาน goAsync ของ Android) — แนะนำ 5 วิ

## พฤติกรรม event ที่ต่างกันต่อ platform

- **Android**: `enterRegion` ยิงทันทีที่เห็น beacon แรก / `exitRegion`
  เมื่อ region เงียบเกิน `max(10s, 2×interval + duration)`
- **iOS**: enter/exit มาจาก OS — exit delay ~30 วิขึ้นไป /
  `enterRegion.beacons` เป็น list ว่างเสมอ (รายละเอียดมากับ `ranged`) /
  `ranged` ไหลเฉพาะ foreground หรือช่วงสั้นหลังถูกปลุก เว้นแต่เปิด
  `continuousRanging` / `txPower` = -1 เสมอ, `distance` = -1 คือยังประมาณไม่ได้

## Ads: `BeaconAds` (เจอ beacon → เด้งโฆษณา)

ส่ง beacon ทุกตัวที่เจอเข้า `showAdNotification` — ที่เหลือ (throttle,
resolve จาก backend, เด้ง notification) SDK จัดการเอง:

```dart
// top-level — ใช้ได้ทั้ง UI isolate และ background callback
final ads = BeaconAds(baseUrl: 'https://ads.example.com');

manager.onBeaconEvent.listen((event) {
  for (final beacon in event.beacons) {
    ads.showAdNotification(beacon); // enter/ranged ยิงได้หมด
  }
});
```

- cooldown ต่อจุดติดตั้ง (default 15 นาที ปรับผ่าน `cooldown:`) — สถานะ
  persist รอด process kill
- ไม่มีโฆษณา / เน็ตล่ม = เงียบ ไม่ throw
- โฆษณาใหม่จุดเดิมแทนที่ notification เก่า (id คงที่ต่อจุด)

## ทดสอบ

beacon ต้องทดสอบบน **device จริง** — simulator/emulator ใช้ไม่ได้
ดูตัวอย่างเต็มใน `example/`
