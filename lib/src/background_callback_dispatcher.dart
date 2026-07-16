import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:background_beacon_sdk/src/models/beacon_event.dart';

/// Callback ฝั่ง app ที่จะถูกเรียกใน background isolate (Android เท่านั้น)
///
/// ต้องเป็น top-level function หรือ static method — closure/instance method
/// ไม่มีที่อยู่ถาวรให้ native เรียกกลับหา ([PluginUtilities.getCallbackHandle]
/// จะคืน null)
///
/// **มีงาน async ข้างใน (ยิง API, โพสต์ notification) ให้ประกาศเป็น
/// `Future<void>` แล้ว await ให้ครบ** — dispatcher await callback นี้เพื่อบอก
/// native ว่างานเสร็จจริงก่อนปล่อย process (fire-and-forget ข้างใน =
/// process อาจโดนเก็บก่อน notification ขึ้น)
///
/// ข้อจำกัดใน isolate นี้: ไม่มี UI/BuildContext, plugin อื่นใช้ได้เท่าที่
/// รองรับ background isolate, ควรทำงานให้จบเร็ว (process อยู่ได้ไม่นาน)
typedef BackgroundBeaconCallback = FutureOr<void> Function(BeaconEvent event);

/// Channel เฉพาะ background isolate — คนละเส้นกับ channel หลัก
/// (isolate ใครก็ตั้ง handler ของตัวเอง ชนกันไม่ได้)
const MethodChannel _backgroundChannel =
    MethodChannel('background_beacon_sdk/background');

/// Entry point ของ background isolate — native (HeadlessBeaconRunner) รัน
/// function นี้ผ่าน callback handle ที่เก็บไว้ตอน registerBackgroundCallback
///
/// `vm:entry-point` จำเป็น: function นี้ไม่มีใครเรียกจากฝั่ง Dart เลย
/// ไม่ใส่ AOT tree-shake ทิ้งแล้ว native หา callback ไม่เจอ
///
/// Flow: native สร้าง engine → รัน dispatcher → dispatcher ตั้ง handler
/// แล้วส่ง `backgroundReady` → native flush event ที่ค้างเข้ามาทาง
/// `onBeaconEvent` ทีละ event
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  // ให้ plugin อื่นใน app ใช้งานได้ใน isolate นี้ (เท่าที่ตัวมันรองรับ)
  DartPluginRegistrant.ensureInitialized();

  _backgroundChannel.setMethodCallHandler((call) async {
    if (call.method != 'onBeaconEvent') return;

    final args = Map<String, dynamic>.from(call.arguments as Map);
    final handle = CallbackHandle.fromRawHandle(args['callbackHandle'] as int);
    final callback = PluginUtilities.getCallbackFromHandle(handle);
    if (callback == null) {
      // app ถูก build ใหม่แล้ว handle เก่าใช้ไม่ได้ — ทิ้ง event
      // (จะหายเองเมื่อ app เปิดแล้ว registerBackgroundCallback ใหม่)
      return;
    }

    final event =
        BeaconEvent.fromMap(Map<String, dynamic>.from(args['event'] as Map));
    // await ให้จบก่อน return — native ถือ goAsync window รอ result ของ
    // handler นี้อยู่ ปล่อยเร็วไป process ตายก่อนงานฝั่ง app เสร็จ
    await (callback as BackgroundBeaconCallback)(event);
  });

  // บอก native ว่า isolate พร้อม — ก่อนหน้านี้ event ถูก queue ไว้ฝั่ง native
  _backgroundChannel.invokeMethod<void>('backgroundReady');
}
