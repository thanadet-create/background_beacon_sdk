import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:background_beacon_sdk/src/platform_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Mock answering detectMobileServices with a preset value, counting invocations
class MockPlatform extends BackgroundBeaconPlatform
    with MockPlatformInterfaceMixin {
  MockPlatform(this.services);

  final String services;
  int detectCalls = 0;

  @override
  Future<String> detectMobileServices() async {
    detectCalls++;
    return services;
  }
}

void main() {
  const detector = PlatformDetector();

  tearDown(() {
    // No reset = every other test in the suite drifts with the last override
    debugDefaultTargetPlatformOverride = null;
  });

  group('PlatformDetector', () {
    test('iOS resolves without asking native', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final mock = MockPlatform('ios');
      BackgroundBeaconPlatform.instance = mock;

      expect(await detector.detectPlatform(), MobilePlatform.ios);
      expect(mock.detectCalls, 0);
    });

    test('Android with GMS resolves to androidGms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      BackgroundBeaconPlatform.instance = MockPlatform('gms');

      expect(await detector.detectPlatform(), MobilePlatform.androidGms);
    });

    test('Android with HMS resolves to androidHms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      BackgroundBeaconPlatform.instance = MockPlatform('hms');

      expect(await detector.detectPlatform(), MobilePlatform.androidHms);
    });

    test('Android with unknown services value falls back to androidGms',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      BackgroundBeaconPlatform.instance = MockPlatform('something-new');

      expect(await detector.detectPlatform(), MobilePlatform.androidGms);
    });

    test('desktop resolves to unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      expect(await detector.detectPlatform(), MobilePlatform.unsupported);
    });
  });
}
