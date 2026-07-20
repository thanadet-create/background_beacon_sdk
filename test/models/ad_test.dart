import 'package:background_beacon_sdk/src/models/ad.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ad', () {
    test('fromJson maps backend fields', () {
      final ad = Ad.fromJson(const {
        'id': '72996320-0ad9-4d37-909e-d7de8e9e673f',
        'title': 'Grand opening',
        'content': '50% off today only',
        'link_url': 'https://example.com/promo',
        'created_at': '2026-07-16T04:35:09.08885Z',
      });

      expect(ad.id, '72996320-0ad9-4d37-909e-d7de8e9e673f');
      expect(ad.title, 'Grand opening');
      expect(ad.content, '50% off today only');
      expect(ad.linkUrl, 'https://example.com/promo');
    });

    test('fromJson tolerates missing link_url', () {
      final ad = Ad.fromJson(const {
        'id': 'x',
        'title': 't',
        'content': 'c',
      });

      expect(ad.linkUrl, '');
    });
  });
}
