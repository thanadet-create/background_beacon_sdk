import 'dart:ui';

import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:background_beacon_sdk/src/background_callback_dispatcher.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:background_beacon_sdk/src/platform_detector.dart';

class BeaconManager {
  // detector to detect platform (ios, androidGms, androidHms, unsupported)
  final PlatformDetector _detector;

  // use ? for nullable type because it will be initialized later in initialize() method
  MobilePlatform? _platform;

  // create getter for native return instance of BackgroundBeaconPlatform
  BackgroundBeaconPlatform get _native => BackgroundBeaconPlatform.instance;

  Stream<BeaconEvent> get onBeaconEvent {
    _ensureInitialized();
    return _native.beaconEvents;
  }

  // constructure create object with default detector
  BeaconManager({PlatformDetector detector = const PlatformDetector()})
      : _detector = detector;

  //initialize method to detect platform and set _platform variable
  Future<MobilePlatform> initialize() async {
    // check if _platform is already initialized, if yes return cached value
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

  // requestPermissions method to request permission from native
  Future<bool> requestPermissions() {
    _ensureInitialized();
    return _native.requestPermissions();
  }

  //start monitoring beacons with given regions and settings
  Future<void> startMonitoring(
      List<BeaconRegion> regions, ScanSettings settings) {
    _ensureInitialized();
    if (regions.isEmpty) {
      throw ArgumentError.value(regions, 'regions', 'must not be empty');
    }
    return _native.startMonitoring(regions, settings);
  }

  // stop monitoring beacons
  Future<void> stopMonitoring() {
    _ensureInitialized();
    return _native.stopMonitoring();
  }

  // detect beacon once
  Future<bool> detectBeacon(BeaconRegion region) {
    _ensureInitialized();
    return _native.detectBeacon(region);
  }

  // register function for background process
  Future<void> registerBackgroundCallback(
      BackgroundBeaconCallback callback) async {
    _ensureInitialized();
    // this work only android os
    if (_platform != MobilePlatform.androidGms &&
        _platform != MobilePlatform.androidHms) {
      return;
    }
    // use pluginUtilities for background process
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

  void _ensureInitialized() {
    if (_platform == null) {
      throw StateError('BeaconManager not initialized');
    }
  }
}
