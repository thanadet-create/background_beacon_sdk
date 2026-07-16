import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_uuid.dart';

void main() {
  group('BeaconRegion', () {
    test('fromMap(toMap()) roundtrip preserves all fields', () {
      final region = BeaconRegion(
        identifier: 'entrance',
        uuid: testFleetUuid,
        major: 100,
        minor: 7,
      );

      expect(BeaconRegion.fromMap(region.toMap()), region);
    });

    test('roundtrip with null major/minor', () {
      final region = BeaconRegion(
        identifier: 'entrance',
        uuid: testFleetUuid,
      );

      final result = BeaconRegion.fromMap(region.toMap());

      expect(result, region);
      expect(result.major, isNull);
      expect(result.minor, isNull);
    });

    test('normalizes uuid to lowercase', () {
      // ป้อนพิมพ์ใหญ่ (แบบที่ iOS รายงาน) ต้องออกมาพิมพ์เล็กเสมอ
      final region = BeaconRegion(
        identifier: 'entrance',
        uuid: testFleetUuid.toUpperCase(),
      );

      expect(region.uuid, testFleetUuid.toLowerCase());
    });

    test('minor without major throws assertion error', () {
      expect(
        () => BeaconRegion(identifier: 'x', uuid: 'abc', minor: 7),
        throwsAssertionError,
      );
    });

    test('wildcard region (no uuid) roundtrips with null uuid', () {
      final region = BeaconRegion(identifier: 'all');

      final result = BeaconRegion.fromMap(region.toMap());

      expect(result, region);
      expect(result.uuid, isNull);
      expect(region.toMap()['uuid'], isNull); // wire contract: ส่ง null จริง
    });

    test('major without uuid throws assertion error', () {
      // wildcard uuid + เจาะจง major = ความหมายกำกวม — บังคับให้ระบุ uuid ก่อน
      expect(
        () => BeaconRegion(identifier: 'x', major: 1),
        throwsAssertionError,
      );
    });

    test('equality compares by value, not reference', () {
      final a = BeaconRegion(identifier: 'x', uuid: 'ABC', major: 1);
      final b = BeaconRegion(identifier: 'x', uuid: 'abc', major: 1);
      final c = BeaconRegion(identifier: 'x', uuid: 'abc', major: 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
