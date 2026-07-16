import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:flutter/services.dart';

/// Default implementation ของ [BackgroundBeaconPlatform]
/// ผ่าน [MethodChannel] + [EventChannel]
///
/// ชั้นนี้รับผิดชอบอย่างเดียว: แปลง model ↔ Map แล้วส่งข้าม channel
/// — ห้ามมี business logic (cache, platform branching ไปอยู่ `BeaconManager`)
///
/// ชื่อ channel ด้านล่างเป็น contract กับ native ทั้งสองฝั่ง
/// (`BackgroundBeaconSdkPlugin.kt` / `.swift` ต้อง register ชื่อเดียวกันเป๊ะ)
class MethodChannelBackgroundBeacon extends BackgroundBeaconPlatform {
  /// ขาคำสั่ง Dart → native: detect / permission / start / stop / detectBeacon
  static const MethodChannel _methodChannel =
      MethodChannel('background_beacon_sdk/methods');

  /// ขา event native → Dart: beacon events ไหลขึ้นทางเดียว
  static const EventChannel _eventChannel =
      EventChannel('background_beacon_sdk/events');

  /// Cache ของ [beaconEvents] — สร้าง map chain ครั้งเดียวแล้ว reuse
  Stream<BeaconEvent>? _beaconEvents;

  @override
  Future<String> detectMobileServices() async {
    final services =
        await _methodChannel.invokeMethod<String>('detectMobileServices');

    if (services == null) {
      // native ต้องตอบเสมอ — null คือบั๊กฝั่ง native ให้พังดัง ๆ ไม่เดาค่า
      // (ต่างจาก requestPermissions ที่ default false แล้วปลอดภัย
      // ค่านี้ชี้ทางเลือก scanner ทั้งระบบ เดาผิดแล้วเงียบจะตามยาก)
      throw StateError('detectMobileServices returned null from native');
    }
    return services;
  }

  @override
  Future<bool> requestPermissions() async {
    final granted =
        await _methodChannel.invokeMethod<bool>('requestPermissions');

    // null = native ตอบไม่ครบ ถือว่าไม่ได้ permission ไว้ก่อน (fail safe)
    return granted ?? false;
  }

  @override
  Future<void> startMonitoring(
      List<BeaconRegion> regions, ScanSettings settings) async {
    await _methodChannel.invokeMethod(
      'startMonitoring',
      {
        'regions': regions.map((e) => e.toMap()).toList(),
        'settings': settings.toMap(),
      },
    );
  }

  @override
  Future<void> stopMonitoring() async {
    await _methodChannel.invokeMethod('stopMonitoring');
  }

  @override
  Future<bool> detectBeacon(BeaconRegion region) async {
    final detected = await _methodChannel.invokeMethod<bool>(
      'detectBeacon',
      region.toMap(),
    );

    return detected ?? false;
  }

  @override
  Future<void> registerBackgroundCallback(
      int dispatcherHandle, int callbackHandle) async {
    await _methodChannel.invokeMethod(
      'registerBackgroundCallback',
      {
        'dispatcherHandle': dispatcherHandle,
        'callbackHandle': callbackHandle,
      },
    );
  }

  @override
  Stream<BeaconEvent> get beaconEvents {
    // event จาก codec มาเป็น Map<Object?, Object?> — ต้อง convert
    // ก่อนเข้า fromMap (nested list ข้างในถูก convert ต่อใน BeaconEvent.fromMap)
    _beaconEvents ??= _eventChannel.receiveBroadcastStream().map((event) =>
        BeaconEvent.fromMap(Map<String, dynamic>.from(event as Map)));

    return _beaconEvents!;
  }
}
