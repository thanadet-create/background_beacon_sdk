import 'dart:async';

import 'package:background_beacon_sdk/background_beacon_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_api.dart';

/// Live Activity (iOS 16.2+) — คุยกับ LiveActivityManager ใน Runner
/// method: start / update, args: {text, count} — ไม่มี end การ์ดอยู่ตลอด
const _liveActivityChannel = MethodChannel(
  'background_beacon_sdk_example/live_activity',
);

Future<void> _liveActivity(String method, String text, int count) async {
  try {
    await _liveActivityChannel.invokeMethod(method, {
      'text': text,
      'count': count,
    });
  } catch (_) {
    // Android / iOS เก่า / extension ยังไม่ได้สร้าง — เงียบ ไม่กระทบ flow หลัก
  }
}

/// กันยิง API/แจ้งเตือนซ้ำจุดเดิมรัว ๆ — ranged มาทุก ~5 วิ
/// นับจาก "ครั้งที่ลอง resolve" ไม่ใช่ครั้งที่เจอโฆษณา — จุดที่ไม่มีโฆษณา (404)
/// จะได้ไม่โดนถามซ้ำทุกรอบ scan
const _adCooldown = Duration(minutes: 3);

/// id แจ้งเตือนคงที่ต่อจุด beacon — โฆษณาจุดเดิมแทนที่ตัวเก่า ไม่กองเป็นตั้ง
/// (hashCode ของ Dart ไม่ stable ข้าม run/isolate — ทำเอง deterministic)
int _adNotificationId(String key) =>
    key.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff);

/// เจอ beacon → ดึงโฆษณาของจุดนั้นจาก backend → เด้งแจ้งเตือน
/// ใช้ได้จากทั้ง UI isolate และ background isolate
/// (แต่ละ isolate ต้อง initialize notification plugin ของตัวเอง)
/// cooldown เก็บใน prefs — background isolate เกิดใหม่ทุกครั้งที่ถูกปลุก
/// ตัวแปร in-memory ใช้กันซ้ำไม่ได้
///
/// [log] — UI isolate ส่ง `_addLog` มาให้ขึ้นแผง log ในจอได้
/// background isolate ไม่มี UI จึงตกไปที่ console แทน
Future<void> showAdNotification(
  Beacon beacon, {
  void Function(String)? log,
}) async {
  final report = log ?? (String line) => debugPrint('ADS: $line');
  final key = '${beacon.uuid}/${beacon.major}/${beacon.minor}';
  final prefs = await SharedPreferences.getInstance();
  final lastAttempt = prefs.getInt('ad_resolved_at/$key') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastAttempt < _adCooldown.inMilliseconds) return;
  await prefs.setInt('ad_resolved_at/$key', now);

  report('ads: ยิง resolve สาขา ${beacon.major} จุด ${beacon.minor}');
  final ad = await resolveAd(
    uuid: beacon.uuid,
    major: beacon.major,
    minor: beacon.minor,
  );
  if (ad == null) {
    // จุดนี้ไม่มีโฆษณา / server ล่ม — ไม่เด้งแจ้งเตือน
    report('ads: ไม่มีโฆษณา สาขา ${beacon.major} จุด ${beacon.minor}');
    return;
  }
  report('ads: เจอ "${ad.title}" → แจ้งเตือน');

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  await notifications.show(
    id: _adNotificationId(key),
    title: ad.title,
    body: ad.content,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'beacon_promo',
        'Beacon promotions',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon SDK Example',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo)),
      home: const BeaconTestPage(),
    );
  }
}

class BeaconTestPage extends StatefulWidget {
  const BeaconTestPage({super.key});

  @override
  State<BeaconTestPage> createState() => _BeaconTestPageState();
}

/// UUID เดียวของทั้ง fleet — scheme ที่ใช้: UUID = ระบบเรา,
/// major = สาขา, minor = จุดติดตั้งในสาขา (map รายละเอียดใน database)
///
/// Override ได้ตอน build: `flutter run --dart-define-from-file=config/dev.json`
/// (ต้องอ่านผ่าน `const` เท่านั้น — non-const จะได้ default เสมอ)
/// fallback = UUID ของ app จำลอง beacon ยอดนิยม (AirLocate)
const _fleetUuid = String.fromEnvironment(
  'BEACON_UUID',
  defaultValue: 'e2c56db5-dffb-48d2-b060-d0f5a71096e0',
);

/// รับ event ตอน app โดน kill (Android) — รันใน background isolate ไม่มี UI
/// ต้องเป็น top-level + `vm:entry-point` กัน AOT tree-shake
/// ดูผลผ่าน `adb logcat | grep BG-BEACON` (setState/context ใช้ไม่ได้ที่นี่)
@pragma('vm:entry-point')
Future<void> onBackgroundBeaconEvent(BeaconEvent event) async {
  debugPrint(
    'BG-BEACON: ${event.type.name} ${event.region} '
    '(${event.beacons.length} beacons)',
  );
  // app โดน kill อยู่ก็เด้งโฆษณาได้ — หัวใจของระบบ
  // ทั้ง enter/ranged เดินเส้นเดียวกัน: cooldown ใน prefs กันยิงซ้ำ
  // (exit มากับ beacons ว่างตามสเปค — loop นี้เป็น no-op เอง)
  // await สำคัญ: dispatcher รอเราเสร็จก่อนปล่อยให้ process ถูกเก็บ
  for (final beacon in event.beacons) {
    await showAdNotification(beacon);
  }
}

class _BeaconTestPageState extends State<BeaconTestPage> {
  final _manager = BeaconManager();

  MobilePlatform? _platform;
  bool _permissionGranted = false;
  bool _monitoring = false;

  StreamSubscription<BeaconEvent>? _subscription;

  /// เก็บเป็น String พร้อมแสดง — event เก่าไม่ต้อง re-render ใหม่
  /// ล่าสุดอยู่บนสุด, จำกัด 100 แถวกัน list โตไม่หยุด (ranged มาถี่)
  final List<String> _log = [];

  /// beacon ที่เห็นล่าสุด key `uuid/major/minor` — สำหรับแผง live ด้านบน
  /// อัปเดตจาก ranged, ลบเมื่อ exit region หรือเงียบเกิน 30 วิ
  final Map<String, _SeenBeacon> _seenBeacons = {};

  @override
  void initState() {
    super.initState();
    _autoStart();
  }

  /// เปิด app แล้ว scan เลยไม่ต้องกดปุ่ม: init → permission → start
  /// dialog permission เด้งเฉพาะครั้งแรก (OS บังคับให้ user กดเอง) —
  /// รอบถัดไปไหลเงียบจนถึง monitoring ไม่มีปุ่มหยุด/เริ่ม
  Future<void> _autoStart() async {
    await _initialize();
    if (_platform == null) return; // init พัง — log บอกแล้ว หยุดแค่นี้
    // การ์ดขึ้นตั้งแต่เปิด app และอยู่ตลอด — ไม่มีจุดสั่ง end อีกแล้ว
    // (หายเองตามระบบ: user ปัดทิ้ง / staleDate / เพดาน ~8 ชม.)
    await _liveActivity('start', 'กำลังหา beacon…', 0);
    await _requestPermissions();
    if (!_permissionGranted) {
      _addLog(
        'auto-start หยุด: ไม่ได้ permission '
        '(เปิดสิทธิ์ใน Settings แล้วเปิด app ใหม่)',
      );
      await _liveActivity('update', 'ไม่ได้ permission', 0);
      return;
    }
    await _requestNotificationPermission();
    await _startMonitoring();
  }

  /// สิทธิ์แจ้งเตือน — Android 13+ / iOS ต้องขอ runtime
  /// โดนปฏิเสธไม่ block การ scan — แค่กล่องแจ้งเตือนไม่โชว์
  Future<void> _requestNotificationPermission() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      _addLog('notification permission failed: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _addLog(String line) {
    // ลง console ด้วย — ดูจากเครื่อง dev ได้ (adb logcat / idevicesyslog)
    // โดยไม่ต้องมี flutter run เกาะอยู่
    debugPrint('BEACON-LOG: $line');
    setState(() {
      final time = TimeOfDay.now();
      _log.insert(
        0,
        '[${time.hour}:${time.minute.toString().padLeft(2, '0')}] $line',
      );
      if (_log.length > 100) _log.removeLast();
    });
  }

  Future<void> _initialize() async {
    try {
      final platform = await _manager.initialize();
      setState(() => _platform = platform);
      _addLog('initialized: ${platform.name}');
    } catch (e) {
      _addLog('initialize failed: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final granted = await _manager.requestPermissions();
      setState(() => _permissionGranted = granted);
      _addLog('permissions: ${granted ? 'granted' : 'denied'}');
    } catch (e) {
      _addLog('requestPermissions failed: $e');
    }
  }

  /// Region เดียวครอบทุก beacon ของ fleet (UUID เดียวกันหมด) —
  /// ใช้ได้เหมือนกันทั้ง iOS/Android, แยกสาขา/จุดจาก major/minor ของแต่ละ beacon
  List<BeaconRegion> _regions() => [
    BeaconRegion(identifier: 'fleet', uuid: _fleetUuid),
  ];

  Future<void> _startMonitoring() async {
    final regions = _regions();
    final settings = ScanSettings(
      scanIntervalMs: 5000,
      scanDurationMs: 2000,
      // widget สถานะสดบนแถบแจ้งเตือน — scan ยังผ่าน PendingIntent (รอด kill)
      foregroundServiceNotification: true,
      beaconLayout: 'iBeacon',
      rangingEnabled: true,
      // iOS: ranging ไหลต่อตอนพับ app (แลกแบต — ปิดได้ถ้าเอาแค่ enter/exit)
      continuousRanging: true,
    );
    try {
      // listen ก่อน start — กัน event ชุดแรกหลุดช่วงรอ await
      _subscription ??= _manager.onBeaconEvent.listen(
        _onEvent,
        onError: (Object e) => _addLog('stream error: $e'),
      );
      // ให้ event ยังถึง Dart แม้ app โดน kill (Android; iOS เป็น no-op)
      await _manager.registerBackgroundCallback(onBackgroundBeaconEvent);
      await _manager.startMonitoring(regions, settings);
      setState(() => _monitoring = true);
      for (final region in regions) {
        _addLog(
          'monitoring ${region.identifier}: '
          '${region.uuid ?? '(all beacons)'}',
        );
      }
    } catch (e) {
      _addLog('startMonitoring failed: $e');
    }
  }

  Future<void> _detectOnce() async {
    final region = _regions().first;
    _addLog('detecting ${region.uuid ?? '(all beacons)'} (3s timeout)...');
    try {
      final found = await _manager.detectBeacon(region);
      _addLog('detectBeacon: ${found ? 'FOUND' : 'not found'}');
    } catch (e) {
      _addLog('detectBeacon failed: $e');
    }
  }

  void _onEvent(BeaconEvent event) {
    switch (event.type) {
      case BeaconEventType.enterRegion:
        _addLog('ENTER ${event.region}');
        for (final beacon in event.beacons) {
          unawaited(showAdNotification(beacon, log: _addLog));
        }
        // 'start' idempotent: มีการ์ดอยู่ = update / ไม่มี (เช่นเพิ่งถูก
        // relaunch จาก kill) = สร้างใหม่ — ครอบทั้งสองเคส
        _liveActivity(
          'start',
          'อยู่ในเขต ${event.region}',
          event.beacons.length,
        );
      case BeaconEventType.exitRegion:
        _addLog('EXIT ${event.region}');
        // การ์ดอยู่ต่อ — แค่บอกสถานะ (ไม่มีการ end จากฝั่ง app แล้ว)
        _liveActivity('update', 'ไม่พบ beacon ในพื้นที่', 0);
        // beacon ของ region นี้ถือว่าหาย — event ไม่บอกราย beacon
        // (beacons ว่างตามสเปค) จึงกวาดด้วย prefix ของ region แทน
        setState(() {
          _seenBeacons.removeWhere((_, s) => s.region == event.region);
        });
      case BeaconEventType.ranged:
        // enter อาจมาพร้อม beacon ตัวแรกตัวเดียว — จุดอื่นในไซต์เดียวกัน
        // โผล่ผ่าน ranged; cooldown ใน showAdNotification กันยิงซ้ำทุก ~5 วิ
        for (final beacon in event.beacons) {
          unawaited(showAdNotification(beacon, log: _addLog));
        }
        setState(() {
          for (final b in event.beacons) {
            _seenBeacons['${b.uuid}/${b.major}/${b.minor}'] = _SeenBeacon(
              beacon: b,
              region: event.region,
            );
          }
          // ตัวที่เงียบเกิน 30 วิถือว่าหาย — กันรายการค้างสะสม
          final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
          _seenBeacons.removeWhere(
            (_, s) => s.beacon.lastSeen.isBefore(cutoff),
          );
        });
        for (final b in event.beacons) {
          _addLog(
            'UUID ${b.uuid} '
            'ranged สาขา ${b.major} จุด ${b.minor} '
            'rssi=${b.rssi} ~${b.distance.toStringAsFixed(1)}m'
            // MAC มีเฉพาะ Android — ใช้เทียบ sticker ข้างเครื่องตอนติดตั้ง
            '${b.mac != null ? ' [${b.mac}]' : ''}',
          );
        }
        if (event.beacons.isNotEmpty) {
          final nearest = event.beacons.reduce(
            (a, b) => a.distance < b.distance ? a : b,
          );
          _liveActivity(
            'update',
            'ใกล้สุด: สาขา ${nearest.major} จุด ${nearest.minor} '
                '~${nearest.distance.toStringAsFixed(1)}m',
            event.beacons.length,
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialized = _platform != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon SDK Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  'platform: ${_platform?.name ?? '-'}   '
                  'permission: ${_permissionGranted ? 'yes' : 'no'}   '
                  'monitoring: ${_monitoring ? 'on' : 'off'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // ทุกขั้น (init/permission/start) รันเองตอนเปิด app
                    // ไม่มีปุ่มหยุด/เริ่ม — scan และ Live Activity อยู่ตลอด
                    OutlinedButton(
                      onPressed:
                          initialized && _permissionGranted && !_monitoring
                          ? _detectOnce
                          : null,
                      child: const Text('Detect once'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildSeenBeaconsPanel(context),
          const Divider(height: 1),
          Expanded(
            child: _log.isEmpty
                ? const Center(child: Text('ยังไม่มี event'))
                : ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      child: Text(
                        _log[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// แผง live ของ beacon ที่เห็นตอนนี้ — เรียงใกล้สุดก่อน
  Widget _buildSeenBeaconsPanel(BuildContext context) {
    final seen = _seenBeacons.values.toList()
      ..sort((a, b) => a.beacon.distance.compareTo(b.beacon.distance));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            'Beacons ที่เห็นตอนนี้ (${seen.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          if (seen.isEmpty)
            Text('— ไม่มี —', style: Theme.of(context).textTheme.bodySmall)
          else
            // จำกัดความสูง — beacon เยอะให้ scroll ในแผงตัวเอง ไม่เบียด log
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView(
                shrinkWrap: true,
                children: [for (final s in seen) _beaconRow(s)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _beaconRow(_SeenBeacon s) {
    final b = s.beacon;
    final ageSec = DateTime.now().difference(b.lastSeen).inSeconds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // ยิ่งใกล้ยิ่งเขียว — เกณฑ์หยาบ ๆ พอไล่สายตาได้
          Icon(
            Icons.bluetooth,
            size: 16,
            color: b.distance < 1
                ? Colors.green
                : b.distance < 5
                ? Colors.orange
                : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              // major/minor = สาขา/จุด ตาม scheme ของ fleet — ชื่อจริง map จาก DB
              // mac (Android เท่านั้น) ไว้เทียบ sticker ข้างเครื่อง
              'สาขา ${b.major}  จุด ${b.minor}  '
              'rssi ${b.rssi}  ~${b.distance.toStringAsFixed(1)}m'
              '${b.mac != null ? '  ${b.mac}' : ''}'
              '${ageSec > 6 ? '  (${ageSec}s ago)' : ''}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Beacon ที่เห็นล่าสุด + region ที่มันสังกัด (ranged event บอก region
/// แต่ตัว Beacon ไม่ได้เก็บ — ผูกไว้ด้วยกันตรงนี้)
class _SeenBeacon {
  const _SeenBeacon({required this.beacon, required this.region});

  final Beacon beacon;
  final String region;
}
