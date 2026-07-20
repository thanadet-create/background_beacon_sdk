import 'dart:convert';

import 'package:background_beacon_sdk/background_beacon_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Beacon beacon({String? uuid}) => Beacon(
        uuid: uuid ?? testFleetUuid,
        major: 100,
        minor: 7,
        rssi: -72,
        txPower: -59,
        distance: 2.5,
        lastSeen: DateTime.parse('2026-07-16T10:30:00.000'),
      );

  http.Response adResponse() => http.Response(
        jsonEncode({
          'ad': {
            'id': 'ad-1',
            'title': 'Grand opening',
            'content': '50% off',
            'link_url': '',
          },
        }),
        200,
      );

  group('BeaconAds.deviceId', () {
    test('generates a v4 uuid once and returns the same value after', () async {
      final ads = BeaconAds(baseUrl: 'https://ads.test');

      final first = await ads.deviceId();
      final second = await ads.deviceId();

      expect(first, second);
      expect(
        first,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });
  });

  group('BeaconAds.resolveAd', () {
    test('parses ad, lowercases uuid, sends X-Device-ID', () async {
      late http.Request captured;
      final ads = BeaconAds(
        baseUrl: 'https://ads.test',
        client: MockClient((request) async {
          captured = request;
          return adResponse();
        }),
      );

      final ad = await ads.resolveAd(
        // iOS reports uppercase — must reach the backend lowercased
        uuid: testFleetUuid.toUpperCase(),
        major: 100,
        minor: 7,
      );

      expect(ad, isNotNull);
      expect(ad!.title, 'Grand opening');
      expect(captured.url.path, '/api/v1/ads/resolve');
      expect(
          captured.url.queryParameters['uuid'], testFleetUuid.toLowerCase());
      expect(captured.url.queryParameters['major'], '100');
      expect(captured.url.queryParameters['minor'], '7');
      expect(captured.headers['X-Device-ID'], isNotEmpty);
    });

    test('returns null on 404 (no ad for this point)', () async {
      final ads = BeaconAds(
        baseUrl: 'https://ads.test',
        client: MockClient(
            (_) async => http.Response('{"error":"not found"}', 404)),
      );

      expect(
        await ads.resolveAd(uuid: testFleetUuid, major: 1, minor: 1),
        isNull,
      );
    });

    test('returns null instead of throwing on network error', () async {
      final ads = BeaconAds(
        baseUrl: 'https://ads.test',
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(
        await ads.resolveAd(uuid: testFleetUuid, major: 1, minor: 1),
        isNull,
      );
    });
  });

  group('BeaconAds.showAdNotification cooldown', () {
    test('second call within cooldown skips the network entirely', () async {
      var requests = 0;
      final ads = BeaconAds(
        baseUrl: 'https://ads.test',
        cooldown: const Duration(minutes: 15),
        client: MockClient((_) async {
          requests++;
          // 404 keeps the flow away from the notifications plugin,
          // which has no platform implementation in unit tests
          return http.Response('{"error":"not found"}', 404);
        }),
      );

      await ads.showAdNotification(beacon(), log: (_) {});
      await ads.showAdNotification(beacon(), log: (_) {});

      expect(requests, 1);
    });

    test('cooldown is keyed per install point', () async {
      var requests = 0;
      final ads = BeaconAds(
        baseUrl: 'https://ads.test',
        client: MockClient((_) async {
          requests++;
          return http.Response('{"error":"not found"}', 404);
        }),
      );

      await ads.showAdNotification(beacon(), log: (_) {});
      // same point but uppercase uuid — must share the same cooldown slot
      await ads.showAdNotification(
        beacon(uuid: testFleetUuid.toUpperCase()),
        log: (_) {},
      );

      expect(requests, 1);
    });
  });
}
