import 'package:background_beacon_sdk/src/models/beacon.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_uuid.dart';

void main() {
  final event = BeaconEvent(
    type: BeaconEventType.enterRegion,
    region: 'entrance',
    beacons: [
      Beacon(
        uuid: testFleetUuid,
        major: 100,
        minor: 7,
        rssi: -72,
        txPower: -59,
        distance: 2.5,
        lastSeen: DateTime.parse('2026-07-09T10:30:00.000'),
      ),
    ],
    timestamp: DateTime.parse('2026-07-09T10:30:01.000'),
  );

  group('BeaconEvent', () {
    test('fromMap(toMap()) roundtrip preserves all fields', () {
      final result = BeaconEvent.fromMap(event.toMap());

      expect(result.type, event.type);
      expect(result.region, event.region);
      expect(result.timestamp, event.timestamp);
      expect(result.beacons, hasLength(1));
      expect(result.beacons.first.uuid, event.beacons.first.uuid);
      expect(result.beacons.first.rssi, event.beacons.first.rssi);
    });

    test('type serializes as enum name without class prefix', () {
      // wire contract กับ native: Kotlin/Swift ส่งแค่ "enterRegion" ไม่ใช่ "BeaconEventType.enterRegion"
      expect(event.toMap()['type'], 'enterRegion');
    });

    test('fromMap accepts nested beacons as Map<Object?, Object?> from codec', () {
      // StandardMethodCodec decode map เป็น Map<Object?, Object?> ไม่ใช่ Map<String, dynamic>
      final map = event.toMap();
      map['beacons'] = (map['beacons'] as List)
          .map((b) => Map<Object?, Object?>.from(b as Map))
          .toList();

      final result = BeaconEvent.fromMap(map);

      expect(result.beacons.first.major, 100);
    });

    test('unknown type string throws', () {
      // behavior ที่เลือกไว้: type ที่ไม่รู้จัก = contract พัง ให้ fail ดัง ๆ ไม่เงียบ
      final map = event.toMap()..['type'] = 'teleported';

      expect(() => BeaconEvent.fromMap(map), throwsArgumentError);
    });

    test('empty beacons list roundtrips', () {
      final exitEvent = BeaconEvent(
        type: BeaconEventType.exitRegion,
        region: 'entrance',
        beacons: [],
        timestamp: DateTime.parse('2026-07-09T10:31:00.000'),
      );

      final result = BeaconEvent.fromMap(exitEvent.toMap());

      expect(result.type, BeaconEventType.exitRegion);
      expect(result.beacons, isEmpty);
    });
  });
}
