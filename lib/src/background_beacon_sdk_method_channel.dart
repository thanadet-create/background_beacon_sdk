import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:flutter/services.dart';

class MethodChannelBackgroundBeacon extends BackgroundBeaconPlatform {
  /// Dart → native: detect / permission / start / stop / detectBeacon
  static const MethodChannel _methodChannel =
      MethodChannel('background_beacon_sdk/methods');

  /// event native → Dart: beacon events
  static const EventChannel _eventChannel =
      EventChannel('background_beacon_sdk/events');

  /// Cache for [beaconEvents]
  Stream<BeaconEvent>? _beaconEvents;

  @override
  Future<String> detectMobileServices() async {
    final services =
        await _methodChannel.invokeMethod<String>('detectMobileServices');

    if (services == null) {
      throw StateError('detectMobileServices returned null from native');
    }
    return services;
  }

  @override
  Future<bool> requestPermissions() async {
    final granted =
        await _methodChannel.invokeMethod<bool>('requestPermissions');

    // null = incomplete native answer; assume no permission (fail safe)
    return granted ?? false;
  }

  @override
  Future<void> startMonitoring(
      List<BeaconRegion> regions, ScanSettings settings) async {
    await _methodChannel.invokeMethod(
      'startMonitoring',
      {
        'regions': regions.map((e) => e.toMap()).toList(),
        'settings': settings.toMap(),
      },
    );
  }

  @override
  Future<void> stopMonitoring() async {
    await _methodChannel.invokeMethod('stopMonitoring');
  }

  @override
  Future<bool> detectBeacon(BeaconRegion region) async {
    final detected = await _methodChannel.invokeMethod<bool>(
      'detectBeacon',
      region.toMap(),
    );

    return detected ?? false;
  }

  @override
  Future<void> registerBackgroundCallback(
      int dispatcherHandle, int callbackHandle) async {
    await _methodChannel.invokeMethod(
      'registerBackgroundCallback',
      {
        'dispatcherHandle': dispatcherHandle,
        'callbackHandle': callbackHandle,
      },
    );
  }

  @override
  Stream<BeaconEvent> get beaconEvents {
    // The codec delivers events as Map<Object?, Object?> — convert before
    // fromMap (nested lists are converted further inside BeaconEvent.fromMap)
    _beaconEvents ??= _eventChannel.receiveBroadcastStream().map((event) =>
        BeaconEvent.fromMap(Map<String, dynamic>.from(event as Map)));

    return _beaconEvents!;
  }
}
