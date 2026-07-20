import 'dart:async';

import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:background_beacon_sdk/src/beacon_manager.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:background_beacon_sdk/src/platform_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'test_uuid.dart';

/// Genuinely top-level — PluginUtilities can find a handle (closures can't)
void topLevelBackgroundCallback(BeaconEvent event) {}

/// Full mock — remembers received arguments and can fire fake events
class MockPlatform extends BackgroundBeaconPlatform
    with MockPlatformInterfaceMixin {
  String services = 'gms';
  int detectCalls = 0;
  bool permissionsResult = true;
  List<BeaconRegion>? lastRegions;
  ScanSettings? lastSettings;
  bool stopCalled = false;
  int? lastDispatcherHandle;
  int? lastCallbackHandle;
  final events = StreamController<BeaconEvent>.broadcast();

  @override
  Future<String> detectMobileServices() async {
    detectCalls++;
    return services;
  }

  @override
  Future<bool> requestPermissions() async => permissionsResult;

  @override
  Future<void> startMonitoring(
      List<BeaconRegion> regions, ScanSettings settings) async {
    lastRegions = regions;
    lastSettings = settings;
  }

  @override
  Future<void> stopMonitoring() async {
    stopCalled = true;
  }

  @override
  Future<void> registerBackgroundCallback(
      int dispatcherHandle, int callbackHandle) async {
    lastDispatcherHandle = dispatcherHandle;
    lastCallbackHandle = callbackHandle;
  }

  @override
  Stream<BeaconEvent> get beaconEvents => events.stream;
}

void main() {
  late MockPlatform mock;
  late BeaconManager manager;

  final region = BeaconRegion(
    identifier: 'entrance',
    uuid: testFleetUuid,
  );
  final settings = ScanSettings(
    scanIntervalMs: 5000,
    scanDurationMs: 1100,
    foregroundServiceNotification: false,
    beaconLayout: 'iBeacon',
    rangingEnabled: false,
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    mock = MockPlatform();
    BackgroundBeaconPlatform.instance = mock;
    manager = BeaconManager();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('initialize', () {
    test('detects platform via native', () async {
      mock.services = 'hms';

      expect(await manager.initialize(), MobilePlatform.androidHms);
    });

    test('is idempotent — detects only once', () async {
      await manager.initialize();
      await manager.initialize();

      expect(mock.detectCalls, 1);
    });

    test('throws UnsupportedError on unsupported platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      expect(manager.initialize(), throwsUnsupportedError);
    });
  });

  group('before initialize', () {
    test('every method throws StateError', () {
      expect(() => manager.requestPermissions(), throwsStateError);
      expect(() => manager.startMonitoring([region], settings),
          throwsStateError);
      expect(() => manager.stopMonitoring(), throwsStateError);
      expect(() => manager.onBeaconEvent, throwsStateError);
    });
  });

  group('after initialize', () {
    setUp(() async {
      await manager.initialize();
    });

    test('startMonitoring rejects empty regions', () {
      expect(() => manager.startMonitoring([], settings), throwsArgumentError);
    });

    test('startMonitoring forwards regions and settings to native', () async {
      await manager.startMonitoring([region], settings);

      expect(mock.lastRegions, [region]);
      expect(mock.lastSettings, settings);
    });

    test('stopMonitoring reaches native', () async {
      await manager.stopMonitoring();

      expect(mock.stopCalled, true);
    });

    test('onBeaconEvent forwards events from native', () async {
      final event = BeaconEvent(
        type: BeaconEventType.enterRegion,
        region: 'entrance',
        beacons: [],
        timestamp: DateTime.parse('2026-07-09T10:30:00.000'),
      );

      final received = manager.onBeaconEvent.first;
      mock.events.add(event);

      expect((await received).region, 'entrance');
    });

    test('registerBackgroundCallback forwards both handles on Android',
        () async {
      await manager.registerBackgroundCallback(topLevelBackgroundCallback);

      // Handles are opaque — just check both were sent and they differ
      expect(mock.lastDispatcherHandle, isNotNull);
      expect(mock.lastCallbackHandle, isNotNull);
      expect(mock.lastDispatcherHandle, isNot(mock.lastCallbackHandle));
    });

    test('registerBackgroundCallback rejects closures', () {
      expect(
        () => manager.registerBackgroundCallback((event) {}),
        throwsArgumentError,
      );
    });
  });

  test('registerBackgroundCallback is a no-op on iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final iosManager = BeaconManager();
    await iosManager.initialize();

    await iosManager.registerBackgroundCallback(topLevelBackgroundCallback);

    expect(mock.lastDispatcherHandle, isNull);
    expect(mock.lastCallbackHandle, isNull);
  });
}
