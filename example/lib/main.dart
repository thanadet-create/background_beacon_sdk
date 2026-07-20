import 'dart:async';

import 'package:background_beacon_sdk/background_beacon_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Live Activity (iOS 16.2+) — talks to LiveActivityManager in Runner.
/// Methods: start / update, args: {text, count} — no end; the card stays up.
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
    // Android / older iOS / extension not created yet — stay silent,
    // never disturb the main flow.
  }
}

/// Ads backend — lives in config/dev.json only (same as BEACON_UUID).
/// No flag = empty string → every resolve fails silently (ads are
/// best-effort, scanning is unaffected) — _startMonitoring logs it once.
const _adsBaseUrl = String.fromEnvironment('ADS_BASE_URL');

/// All timing values come from config/dev.json — tune them during field
/// tests without touching code. (Must be read via `const` only — non-const
/// reads always get the default.) Defaults are kept for the numbers:
/// a missing flag would silently yield 0 (int.fromEnvironment), and
/// scanIntervalMs = 0 means non-stop scanning.
const _scanIntervalMs = int.fromEnvironment(
  'SCAN_INTERVAL_MS',
  defaultValue: 5000,
);
const _scanDurationMs = int.fromEnvironment(
  'SCAN_DURATION_MS',
  defaultValue: 2000,
);
const _adCooldownMinutes = int.fromEnvironment(
  'AD_COOLDOWN_MINUTES',
  defaultValue: 3,
);

/// One instance shared by the UI isolate and the background isolate —
/// top-level because the background isolate has no State; cooldown state
/// already lives in prefs. Cooldown is shorter than the SDK default so
/// repeated testing is quick.
final _ads = BeaconAds(
  baseUrl: _adsBaseUrl,
  cooldown: const Duration(minutes: _adCooldownMinutes),
);

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

/// Single UUID for the whole fleet — scheme: UUID = our system,
/// major = branch, minor = install point (details mapped in the database).
///
/// Lives in config/dev.json only — no fallback in code: running without
/// `--dart-define-from-file=config/dev.json` yields an empty string and
/// _startMonitoring stops with a message (better than silently scanning
/// for the wrong UUID).
const _fleetUuid = String.fromEnvironment('BEACON_UUID');

/// Receives events after the app is killed (Android) — runs in a background
/// isolate with no UI. Must be top-level + `vm:entry-point` so AOT doesn't
/// tree-shake it. Watch via `adb logcat | grep BG-BEACON`
/// (setState/context are unusable here).
@pragma('vm:entry-point')
Future<void> onBackgroundBeaconEvent(BeaconEvent event) async {
  debugPrint(
    'BG-BEACON: ${event.type.name} ${event.region} '
    '(${event.beacons.length} beacons)',
  );
  // Ads still pop while the app is killed — the heart of the system.
  // enter/ranged share one path: the prefs cooldown dedupes repeats.
  // (exit carries an empty beacons list per spec — this loop no-ops.)
  // The await matters: the dispatcher waits for us before letting the
  // process be reclaimed.
  for (final beacon in event.beacons) {
    await _ads.showAdNotification(beacon);
  }
}

class _BeaconTestPageState extends State<BeaconTestPage> {
  final _manager = BeaconManager();

  MobilePlatform? _platform;
  bool _permissionGranted = false;
  bool _monitoring = false;

  StreamSubscription<BeaconEvent>? _subscription;

  /// Stored as display-ready Strings — old events never re-render.
  /// Newest first, capped at 100 rows so the list can't grow unbounded
  /// (ranged arrives often).
  final List<String> _log = [];

  /// Recently seen beacons keyed `uuid/major/minor` — feeds the live panel
  /// up top. Updated from ranged; removed on region exit or after 30 s
  /// of silence.
  final Map<String, _SeenBeacon> _seenBeacons = {};

  @override
  void initState() {
    super.initState();
    _autoStart();
  }

  /// Scan immediately on launch, no button: init → permission → start.
  /// The permission dialog appears only on first run (the OS requires the
  /// user's tap) — later runs flow silently into monitoring. No stop/start
  /// buttons.
  Future<void> _autoStart() async {
    await _initialize();
    if (_platform == null) return; // init failed — already logged, stop here
    // The card appears at launch and stays — nothing ever calls end.
    // (It disappears on its own: user swipe / staleDate / ~8 h system cap.)
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

  /// Notification permission — Android 13+ / iOS require a runtime request.
  /// Denial doesn't block scanning — ad notifications just won't show.
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
    // Mirror to console — visible from the dev machine (adb logcat /
    // idevicesyslog) without a flutter run session attached.
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

  /// One region covers every beacon in the fleet (they share one UUID) —
  /// works identically on iOS/Android; branch/point come from each
  /// beacon's major/minor.
  List<BeaconRegion> _regions() => [
    BeaconRegion(identifier: 'fleet', uuid: _fleetUuid),
  ];

  Future<void> _startMonitoring() async {
    if (_fleetUuid.isEmpty) {
      _addLog('empty BEACON_UUID value');
      return;
    }
    if (_adsBaseUrl.isEmpty) {
      // Broken ads never block scanning — one warning at start is enough.
      _addLog('empty ADS_BASE_URL value — ads disabled');
    }
    final regions = _regions();
    final settings = ScanSettings(
      scanIntervalMs: _scanIntervalMs,
      scanDurationMs: _scanDurationMs,
      // Live status widget on the notification shade — scanning still goes
      // through PendingIntent (survives kill).
      foregroundServiceNotification: true,
      beaconLayout: 'iBeacon',
      rangingEnabled: true,
      // iOS: ranging keeps flowing while backgrounded — keep-alive runs only
      // while inside a region (starts on first enter, stops after leaving
      // all). Turn off if enter/exit alone is enough.
      continuousRanging: true,
    );
    try {
      // Listen before start — don't lose the first events during the await.
      _subscription ??= _manager.onBeaconEvent.listen(
        _onEvent,
        onError: (Object e) => _addLog('stream error: $e'),
      );
      // Keep events reaching Dart even after the app is killed
      // (Android; no-op on iOS).
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
          unawaited(_ads.showAdNotification(beacon, log: _addLog));
        }
        // 'start' is idempotent: card exists = update / none (e.g. just
        // relaunched from kill) = create — covers both cases.
        _liveActivity(
          'start',
          'อยู่ในเขต ${event.region}',
          event.beacons.length,
        );
      case BeaconEventType.exitRegion:
        _addLog('EXIT ${event.region}');
        // Card stays up — just report status (the app never calls end).
        _liveActivity('update', 'ไม่พบ beacon ในพื้นที่', 0);
        // All beacons of this region are considered gone — the event names
        // no beacons (empty list per spec), so sweep by region instead.
        setState(() {
          _seenBeacons.removeWhere((_, s) => s.region == event.region);
        });
      case BeaconEventType.ranged:
        // enter may carry only the first beacon — other points on the same
        // site surface via ranged; the cooldown inside showAdNotification
        // stops re-fires every ~5 s.
        for (final beacon in event.beacons) {
          unawaited(_ads.showAdNotification(beacon, log: _addLog));
        }
        setState(() {
          for (final b in event.beacons) {
            _seenBeacons['${b.uuid}/${b.major}/${b.minor}'] = _SeenBeacon(
              beacon: b,
              region: event.region,
            );
          }
          // Silent for over 30 s = gone — keeps stale rows from piling up.
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
            // MAC is Android-only — matched against the device sticker
            // during installation.
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
                    // Every step (init/permission/start) runs itself at
                    // launch. No stop/start buttons — scanning and the
                    // Live Activity are always on.
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

  /// Live panel of currently visible beacons — nearest first.
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
            // Cap the height — many beacons scroll inside their own panel
            // instead of squeezing the log.
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
          // Greener when closer — rough thresholds, enough to eyeball.
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
              // major/minor = branch/point per fleet scheme — real names map
              // from the DB. mac (Android-only) matches the device sticker.
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

/// A recently seen beacon plus the region it belongs to (the ranged event
/// names the region but Beacon itself doesn't carry it — tied together here).
class _SeenBeacon {
  const _SeenBeacon({required this.beacon, required this.region});

  final Beacon beacon;
  final String region;
}
