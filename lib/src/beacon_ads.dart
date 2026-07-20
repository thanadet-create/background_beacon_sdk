import 'dart:convert';
import 'dart:math';

import 'package:background_beacon_sdk/src/models/ad.dart';
import 'package:background_beacon_sdk/src/models/beacon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BeaconAds {
  /// Root URL of the ads backend
  final String baseUrl;
  final Duration cooldown;

  /// Android notification channel and small icon used for ad notifications.
  final String androidChannelId;
  final String androidChannelName;
  final String androidIcon;

  final http.Client _client;

  BeaconAds({
    required this.baseUrl,
    this.cooldown = const Duration(minutes: 15),
    this.androidChannelId = 'beacon_ads',
    this.androidChannelName = 'Beacon ads',
    this.androidIcon = '@mipmap/ic_launcher',
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const _deviceIdKey = 'background_beacon_sdk.device_id';
  static const _attemptKeyPrefix = 'background_beacon_sdk.ad_resolved_at/';

  /// Per-install device ID sent as `X-Device-ID` on every resolve request.
  /// Generated on first call and persisted; survives until the app's data
  /// is cleared or the app is uninstalled.
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;

    final id = _uuidV4();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  /// Fetches the ad mapped to one install point via
  /// `GET /api/v1/ads/resolve`. Returns null when the point has no ad (404)
  /// or the request fails — ads are best-effort and must never throw into
  /// the caller's event loop.
  Future<Ad?> 
  resolveAd({
    required String uuid,
    required int major,
    required int minor,
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/ads/resolve'
      '?uuid=${uuid.toLowerCase()}&major=$major&minor=$minor',
    );
    try {
      final response = await _client.get(url, headers: {
        'X-Device-ID': await deviceId()
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Ad.fromJson(body['ad'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('BeaconAds: resolve failed for $major/$minor: $e');
      return null;
    }
  }

  // app notification
  Future<void> showAdNotification(
    Beacon beacon, {
    void Function(String)? log,
  }) async {
    final report = log ?? (String line) => debugPrint('BeaconAds: $line');
    final key = '${beacon.uuid.toLowerCase()}/${beacon.major}/${beacon.minor}';
    final prefs = await SharedPreferences.getInstance();
    final lastAttempt = prefs.getInt('$_attemptKeyPrefix$key') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastAttempt < cooldown.inMilliseconds) return;
    await prefs.setInt('$_attemptKeyPrefix$key', now);

    report('ads: resolving ${beacon.major}/${beacon.minor}');
    final ad = await resolveAd(
      uuid: beacon.uuid,
      major: beacon.major,
      minor: beacon.minor,
    );
    if (ad == null) {
      report('ads: no ad for ${beacon.major}/${beacon.minor}');
      return;
    }
    report('ads: "${ad.title}" -> notification');

    // Each isolate initializes its own plugin instance; repeated calls are
    // cheap no-ops.
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(androidIcon),
        iOS: const DarwinInitializationSettings(),
      ),
    );

    await notifications.show(
      // Deterministic id per install point so a newer ad for the same spot
      // replaces the old notification instead of stacking. (Dart's
      // hashCode is not stable across runs/isolates.)
      id: beacon.uuid.codeUnits.followedBy([beacon.major, beacon.minor]).fold(
          0, (h, c) => (h * 31 + c) & 0x7fffffff),
      title: ad.title,
      body: ad.content,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannelId,
          androidChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// UUID v4 from Random.secure
  static String _uuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
