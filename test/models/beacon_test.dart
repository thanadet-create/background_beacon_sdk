import 'package:background_beacon_sdk/src/models/beacon.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_uuid.dart';

void main() {
  final beacon = Beacon(
    uuid: testFleetUuid,
    major: 100,
    minor: 7,
    rssi: -72,
    txPower: -59,
    distance: 2.5,
    lastSeen: DateTime.parse('2026-07-09T10:30:00.000'),
    mac: 'c3:00:00:1d:69:94',
  );

  group('Beacon', () {
    test('fromMap(toMap()) roundtrip preserves all fields', () {
      final result = Beacon.fromMap(beacon.toMap());

      expect(result.uuid, beacon.uuid);
      expect(result.major, beacon.major);
      expect(result.minor, beacon.minor);
      expect(result.rssi, beacon.rssi);
      expect(result.txPower, beacon.txPower);
      expect(result.distance, beacon.distance);
      expect(result.lastSeen, beacon.lastSeen);
      expect(result.mac, beacon.mac);
    });

    test('fromMap accepts distance sent as int', () {
      final map = beacon.toMap()..['distance'] = -1;

      final result = Beacon.fromMap(map);

      expect(result.distance, -1.0);
      expect(result.distance, isA<double>());
    });

    test('fromMap without mac key reads null (iOS never sends it)', () {
      final map = beacon.toMap()..remove('mac');

      expect(Beacon.fromMap(map).mac, isNull);
    });
  });
}
