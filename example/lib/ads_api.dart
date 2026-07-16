import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ads backend — resolve โฆษณาจากตัวตน beacon (uuid/major/minor)
/// ใช้ได้จากทั้ง UI isolate และ background isolate (http เป็น pure Dart,
/// shared_preferences ใช้ channel ซึ่ง headless engine ลงทะเบียน plugin ให้แล้ว)
///
/// URL ตั้งได้ตอน build: `flutter run --dart-define-from-file=config/dev.json`
/// (แบบเดียวกับ BEACON_UUID — ต้องอ่านผ่าน `const` เท่านั้น)
/// fallback = ngrok ตัว dev ปัจจุบัน — URL หมุนใหม่เมื่อ restart ngrok
/// แก้ที่ config/dev.json ไม่ต้องแตะโค้ด
const _baseUrl = String.fromEnvironment(
  'ADS_BASE_URL',
  defaultValue: 'https://overinsistent-julieta-lollingly.ngrok-free.dev',
);

/// โฆษณาจาก `GET /api/v1/ads/resolve` — field ตาม response จริงของ server
class Ad {
  const Ad({
    required this.id,
    required this.title,
    required this.content,
    required this.linkUrl,
  });

  factory Ad.fromJson(Map<String, dynamic> json) => Ad(
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    linkUrl: json['link_url'] as String? ?? '',
  );

  final String id;
  final String title;
  final String content;
  final String linkUrl;
}

/// Device ID ประจำเครื่อง — generate ครั้งแรกที่ถูกเรียกหลัง install
/// แล้ว persist ตลอดอายุ app (หายเมื่อ uninstall/ล้างข้อมูลเท่านั้น)
Future<String> deviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString('device_id');
  if (existing != null) return existing;

  final id = _uuidV4();
  await prefs.setString('device_id', id);
  return id;
}

/// UUID v4 จาก Random.secure — พอสำหรับ device ID ไม่ต้องพึ่ง package uuid
String _uuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// ดึงโฆษณาของจุดติดตั้ง (uuid, major, minor) — null เมื่อไม่มีโฆษณา (404)
/// หรือ server/เน็ตล่ม: แจ้งเตือนเป็น best-effort ห้าม throw ใส่ event loop
Future<Ad?> resolveAd({
  required String uuid,
  required int major,
  required int minor,
}) async {
  final url = Uri.parse(
    '$_baseUrl/api/v1/ads/resolve?uuid=$uuid&major=$major&minor=$minor',
  );
  try {
    final response = await http
        .get(url, headers: {'X-Device-ID': await deviceId()})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return Ad.fromJson(body['ad'] as Map<String, dynamic>);
  } catch (e) {
    debugPrint('ADS: resolve failed for $major/$minor: $e');
    return null;
  }
}
