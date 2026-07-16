# background_beacon_sdk

Flutter plugin สำหรับรับสัญญาณ BLE beacon ขณะ background — รองรับ iOS / Android (GMS) / Huawei (HMS) โดย SDK detect platform เองอัตโนมัติ

## Architecture

- **Single package + platform interface pattern** — app import package เดียว เรียก `BeaconManager` ตัวเดียว
- **Huawei ไม่ใช่ platform แยกของ Flutter** — เป็น Android ที่ไม่มี GMS จึงแยกกันที่ runtime ฝั่ง native (`MobileServicesDetector.kt`) ไม่ใช่แยกโฟลเดอร์ platform
- Data flow: `BeaconManager` (facade) → `BackgroundBeaconSdkPlatform` (interface) → `MethodChannelBackgroundBeaconSdk` → native plugin → scanner/monitor → EventChannel → `Stream<BeaconEvent>` กลับสู่ app

## Folder structure

```
background_beacon_sdk/            # ชื่อโฟลเดอร์ต้องตรงชื่อ package — SwiftPM ใช้เป็น package identity
├── pubspec.yaml                  # ประกาศ plugin platforms (android/ios)
├── lib/
│   ├── background_beacon_sdk.dart            # public API — export ที่เดียว
│   └── src/
│       ├── beacon_manager.dart               # facade ที่ app ใช้
│       ├── platform_detector.dart            # detect ios / androidGms / androidHms
│       ├── background_beacon_sdk_platform_interface.dart
│       ├── background_beacon_sdk_method_channel.dart
│       └── models/                           # beacon, region, event, settings
├── android/
│   └── src/main/kotlin/.../background_beacon_sdk/
│       ├── BackgroundBeaconSdkPlugin.kt      # channel entry point
│       ├── core/                             # scanner interface, parser, service, receiver
│       ├── gms/                              # scanner สำหรับ GMS device
│       ├── hms/                              # scanner สำหรับ Huawei device
│       └── util/MobileServicesDetector.kt    # เช็ค GMS vs HMS
├── ios/
│   ├── background_beacon_sdk.podspec         # CocoaPods (ยังต้องมีคู่กับ SPM)
│   └── background_beacon_sdk/                # Swift Package (layout ตาม SPM)
│       ├── Package.swift
│       └── Sources/background_beacon_sdk/    # plugin, BeaconMonitor, permissions
└── example/                                  # ตัวอย่าง app (สร้างด้วย flutter create)
```

## Background strategy ต่อ platform

| Platform | กลไก | ข้อจำกัด |
|---|---|---|
| iOS | CLBeaconRegion monitoring — OS ปลุก app แม้โดน kill | ranging ได้เฉพาะ foreground/ช่วงสั้น, จำกัด 20 regions |
| Android GMS | BLE scan ผ่าน PendingIntent (API 26+) หรือ foreground service | foreground service ต้องมี notification |
| Android HMS | เหมือน GMS (BLE ไม่พึ่ง GMS) | EMUI battery optimization ดุ — ต้อง whitelist |

### Scheme ที่ใช้ deploy จริง (ตัดสินใจแล้ว 2026-07-13)

**UUID เดียวทั้ง fleet / major = รหัสสาขา / minor = จุดติดตั้งในสาขา**
รายละเอียด (ชื่อสาขา, โซน) map จาก database ด้วยคู่ (major, minor)

- ทำงานเต็มรูปแบบทั้งสอง platform — iOS ประกาศ region เดียว (UUID) ก็ครอบ
  ทุก beacon ของระบบ, แยกสาขาจาก `beacon.major` ใน ranged event
- อยาก enter/exit รายสาขาบน iOS: region ต่อสาขา `BeaconRegion(uuid, major:)`
  ได้สูงสุด 20 สาขาพร้อมกัน (เลือก monitor เฉพาะสาขาใกล้ user ถ้าเกิน)
- อย่าฝังความหมายใน minor (เช่นหลักร้อย = ชั้น) — เก็บใน DB จะเปลี่ยน layout
  ได้โดยไม่ต้อง flash beacon ใหม่
- iBeacon ไม่มี auth — ใครก็ spoof UUID/major/minor ได้ business logic
  ที่ผูกสิทธิ์/เงินต้อง verify ฝั่ง server เพิ่ม

### Wildcard region (รับทุก UUID)

`BeaconRegion(identifier: 'all')` ไม่ระบุ uuid = จับ iBeacon ทุกตัว — **Android
เท่านั้น**: iOS ปฏิเสธตอน start (`START_FAILED`) เพราะ `CLBeaconRegion` บังคับ
รู้ UUID ล่วงหน้า และ CoreBluetooth ก็อ่าน iBeacon frame ไม่ได้ (Apple ตัด
manufacturer data ทิ้ง — BLE scanner app บน iOS จึงเห็นแค่ว่ามีเครื่องอยู่
แต่ไม่เห็น UUID/major/minor) → บน iOS ให้ดึงรายชื่อ UUID จาก backend
มาสร้าง region แทน (เพดาน 20)

### Android: โหมด scan (เลือกผ่าน `ScanSettings.foregroundServiceNotification`)

- **`false` (default แนะนำ)** — PendingIntent scan: OS scan ให้เองแบบ LOW_POWER
  แล้วปลุก `BeaconScanReceiver` เป็น batch ทุก ~`scanIntervalMs`
  ประหยัดแบต ตัว scan รอด process kill / API < 26 fallback เป็น duty cycle ธรรมดา
- **`true`** — foreground service (notification ค้าง) กัน process ตาย
  + duty cycle scan: LOW_LATENCY นาน `scanDurationMs` พักจนครบ `scanIntervalMs`
  ใช้เมื่อต้อง ranging ต่อเนื่อง

Event ฝั่ง Android:
- `enterRegion` ยิงทันทีที่เห็น beacon แรกของ region
- `ranged` aggregate หนึ่ง event ต่อ region ต่อรอบ scan (ไม่ยิงราย advertisement)
- `exitRegion` เมื่อ region เงียบเกิน `max(10s, 2×interval + duration)`

### Android: รับ event แม้ app โดน kill (headless engine)

```dart
@pragma('vm:entry-point')            // กัน AOT tree-shake
void onBgEvent(BeaconEvent event) {  // ต้องเป็น top-level / static
  // รันใน background isolate — ไม่มี UI/BuildContext
}

await manager.registerBackgroundCallback(onBgEvent); // ก่อน startMonitoring
```

กลไก: `BeaconScanReceiver` ถูกปลุกโดยไม่มี engine → `HeadlessBeaconRunner`
สร้าง `FlutterEngine` ใหม่ รัน `backgroundCallbackDispatcher` ผ่าน callback
handle ที่ persist ไว้ → ส่ง event เข้า callback ของ app / engine ถูก cache
ตลอดอายุ process — batch ถัดไปไม่ต้อง spin-up ใหม่ / iOS ไม่ต้องใช้กลไกนี้
(OS relaunch app ทั้งตัว event เข้า stream ปกติ) — เรียกได้ เป็น no-op

ข้อจำกัด headless mode:
- ใช้ได้เฉพาะโหมด PendingIntent (`foregroundServiceNotification: false`)
- state enter/exit เริ่มว่างหลัง process ตาย — beacon ที่ยังอยู่ในเขตได้
  enter ซ้ำหนึ่งครั้ง
- exit ตรวจได้เฉพาะตอนถูกปลุก — ถ้าไม่มี beacon ใดปลุกเลย exit ค้างจนกว่า
  จะถูกปลุกครั้งถัดไป/เปิด app
- rebuild app แล้ว callback handle เก่าใช้ไม่ได้ — event ถูกทิ้งจนกว่าจะเปิด
  app แล้ว register ใหม่
- reboot: `BootReceiver` re-register scan ให้อัตโนมัติ (เฉพาะโหมด PendingIntent)
- Huawei/EMUI: user ต้อง whitelist battery optimization ไม่งั้นระบบฆ่าทุกกลไก

### iOS: พฤติกรรมที่ต่างจาก Android

- enter/exit มาจาก OS region monitoring — ไม่มี state machine ฝั่ง SDK
  exit จึง delay ตามจังหวะของระบบ (~30 วิขึ้นไป)
- `enterRegion` beacons เป็น list ว่างเสมอ (monitoring รู้แค่ "เข้าเขต"
  รายละเอียดราย beacon มากับ `ranged`)
- `ranged` ไหลเฉพาะตอน foreground หรือช่วงสั้น ๆ (~10 วิ) หลัง OS ปลุก app
- `txPower` เป็น -1 เสมอ, `distance` = `CLBeacon.accuracy` (-1 = ยังประมาณไม่ได้)
- app โดน kill แล้วเข้าเขต beacon → OS relaunch app ให้ — event ที่เกิดก่อน
  Dart เริ่ม listen ถูก buffer ไว้ flush ตอน listen (เพดาน 100 event)
- `ScanSettings` ใช้แค่ `rangingEnabled` — interval/duration/notification
  เป็นเรื่องของ Android

## Implement ลำดับแนะนำ

1. Dart models + platform interface + method channel (test ด้วย mock ได้เลย)
2. Android: plugin entry + `MobileServicesDetector` + BLE scan foreground ก่อน
3. Android background: `BeaconScanReceiver` (PendingIntent scan)
4. iOS: `BeaconMonitor` region monitoring + relaunch handling
5. `example/` app ทดสอบจริง (beacon ต้องทดสอบบน device จริง — simulator ใช้ไม่ได้)

## Known issue: build บนเครื่อง locale ไทย

Gradle บนเครื่องที่ system locale เป็นไทยจะพังที่ `mergeDebugJavaResource`
(`VerifyException` จาก `MsDosDateTimeUtils.packDate`) — `Calendar.getInstance()`
ได้ปฏิทินพุทธ ปี 2569 เกินเพดาน zip date format (ค.ศ. 2107)
แก้โดยเติมใน `android/gradle.properties` ของ app:

```
org.gradle.jvmargs=-Duser.language=en -Duser.country=US <flags เดิม...>
```

## App-side requirements (จดไว้ใน doc ให้คน integrate)

- iOS: Info.plist ต้องมี `NSLocationAlwaysAndWhenInUseUsageDescription`, background modes: `location`, `bluetooth-central`
- Android: `requestPermissions()` ขอให้ครบสองจังหวะแล้ว (foreground →
  `ACCESS_BACKGROUND_LOCATION`) — API 30+ ระบบพาไปหน้า Settings, user ต้อง
  เลือก **"Allow all the time"** เอง ไม่งั้นผล scan หยุดทันทีที่ app ลง
  background / API 33+ ควรขอ `POST_NOTIFICATIONS` ถ้าใช้โหมด foreground
  service ไม่งั้น notification ไม่โชว์
- Huawei: ถ้าใช้ HMS Location Kit ต้องเพิ่ม Huawei maven repo + agconnect config
