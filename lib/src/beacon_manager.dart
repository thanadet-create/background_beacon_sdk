import 'dart:ui';

import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:background_beacon_sdk/src/background_callback_dispatcher.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:background_beacon_sdk/src/platform_detector.dart';

/// Facade the app talks to — methods below appear in the order an app
/// should call them: initialize → requestPermissions → onBeaconEvent →
/// registerBackgroundCallback → startMonitoring → stopMonitoring.
class BeaconManager {
  // detector to detect platform (ios, androidGms, androidHms, unsupported)
  final PlatformDetector _detector;

  // nullable: set once by initialize(), guards every other method
  MobilePlatform? _platform;

  BeaconManager({PlatformDetector detector = const PlatformDetector()})
      : _detector = detector;

  // getter so tests can swap BackgroundBeaconPlatform.instance underneath
  BackgroundBeaconPlatform get _native => BackgroundBeaconPlatform.instance;

  /// Detect the platform once and cache it — every other method throws
  /// [StateError] until this has completed.
  Future<MobilePlatform> initialize() async {
    final cached = _platform;
    if (cached != null) return cached;

    final detected = await _detector.detectPlatform();
    if (detected == MobilePlatform.unsupported) {
      throw UnsupportedError(
          'background_beacon_sdk supports iOS and Android only');
    }
    _platform = detected;
    return detected;
  }

  /// Request every permission scanning needs (Android asks in two steps:
  /// foreground first, then background location).
  Future<bool> requestPermissions() {
    _ensureInitialized();
    return _native.requestPermissions();
  }

  /// Listen before [startMonitoring] so no early event is lost.
  Stream<BeaconEvent> get onBeaconEvent {
    _ensureInitialized();
    return _native.beaconEvents;
  }

  /// Register the callback that receives events after the app is killed
  /// (Android only — no-op on iOS). Call before [startMonitoring].
  Future<void> registerBackgroundCallback(
      BackgroundBeaconCallback callback) async {
    _ensureInitialized();
    if (_platform != MobilePlatform.androidGms &&
        _platform != MobilePlatform.androidHms) {
      return;
    }
    // PluginUtilities gives a stable handle only for top-level/static
    // functions — anything else can't be called back from native
    final callbackHandle = PluginUtilities.getCallbackHandle(callback);
    if (callbackHandle == null) {
      throw ArgumentError.value(callback, 'callback',
          'must be a top-level function or static method');
    }

    final dispatcherHandle =
        PluginUtilities.getCallbackHandle(backgroundCallbackDispatcher)!;

    await _native.registerBackgroundCallback(
        dispatcherHandle.toRawHandle(), callbackHandle.toRawHandle());
  }

  /// Start scanning — calling again replaces the previous region set.
  Future<void> startMonitoring(
      List<BeaconRegion> regions, ScanSettings settings) {
    _ensureInitialized();
    if (regions.isEmpty) {
      throw ArgumentError.value(regions, 'regions', 'must not be empty');
    }
    return _native.startMonitoring(regions, settings);
  }

  Future<void> stopMonitoring() {
    _ensureInitialized();
    return _native.stopMonitoring();
  }

  void _ensureInitialized() {
    if (_platform == null) {
      throw StateError('BeaconManager not initialized');
    }
  }
}
