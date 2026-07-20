import 'package:background_beacon_sdk/src/background_beacon_sdk_method_channel.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('background_beacon_sdk/methods');
  const eventChannelName = 'background_beacon_sdk/events';
  const codec = StandardMethodCodec();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final platform = MethodChannelBackgroundBeacon();
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'detectMobileServices':
          return 'hms';
        case 'requestPermissions':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  group('MethodChannelBackgroundBeacon', () {
    test('detectMobileServices returns value from native', () async {
      expect(await platform.detectMobileServices(), 'hms');
    });

    test('requestPermissions returns false when native returns null', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async => null);

      expect(await platform.requestPermissions(), false);
    });

    test('startMonitoring sends regions and settings as maps', () async {
      final regions = [
        BeaconRegion(
          identifier: 'entrance',
          uuid: testFleetUuid,
          major: 100,
        ),
      ];
      final settings = ScanSettings(
        scanIntervalMs: 5000,
        scanDurationMs: 1100,
        foregroundServiceNotification: true,
        beaconLayout: 'iBeacon',
        rangingEnabled: false,
      );

      await platform.startMonitoring(regions, settings);

      expect(log, hasLength(1));
      expect(log.first.method, 'startMonitoring');
      final args = log.first.arguments as Map;
      expect(args['regions'], [regions.first.toMap()]);
      expect(args['settings'], settings.toMap());
    });

    test('beaconEvents decodes event map from native into BeaconEvent',
        () async {
      // ack the EventChannel's listen/cancel
      messenger.setMockMessageHandler(eventChannelName,
          (message) async => codec.encodeSuccessEnvelope(null));

      final firstEvent = platform.beaconEvents.first;
      await pumpEventQueue();

      // Inject the event through the real codec — the map decodes as
      // Map<Object?, Object?> just like native sends, testing the whole cast chain
      await messenger.handlePlatformMessage(
        eventChannelName,
        codec.encodeSuccessEnvelope(<String, dynamic>{
          'type': 'enterRegion',
          'region': 'entrance',
          'beacons': [
            {
              'uuid': testFleetUuid,
              'major': 100,
              'minor': 7,
              'rssi': -72,
              'txPower': -59,
              'distance': 2.5,
              'lastSeen': '2026-07-09T10:30:00.000',
            },
          ],
          'timestamp': '2026-07-09T10:30:01.000',
        }),
        (_) {},
      );

      final event = await firstEvent;
      expect(event.type, BeaconEventType.enterRegion);
      expect(event.region, 'entrance');
      expect(event.beacons.single.major, 100);

      messenger.setMockMessageHandler(eventChannelName, null);
    });
  });
}
