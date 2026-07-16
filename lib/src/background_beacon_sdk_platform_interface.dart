import 'package:background_beacon_sdk/src/background_beacon_sdk_method_channel.dart';
import 'package:background_beacon_sdk/src/models/beacon_event.dart';
import 'package:background_beacon_sdk/src/models/beacon_region.dart';
import 'package:background_beacon_sdk/src/models/scan_settings.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class BackgroundBeaconPlatform extends PlatformInterface {
  static final Object _token = Object();
  static BackgroundBeaconPlatform _instance = MethodChannelBackgroundBeacon();

  BackgroundBeaconPlatform() : super(token: _token);

  static BackgroundBeaconPlatform get instance => _instance;

  static set instance(BackgroundBeaconPlatform value) {
    PlatformInterface.verifyToken(value, _token);
    _instance = value;
  }

  // ios, gms, hms
  Future<String> detectMobileServices() {
    throw UnimplementedError(
        'detectMobileServices() has not been implemented.');
  }

  // request permission
  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  Future<void> startMonitoring(
      List<BeaconRegion> regions, ScanSettings settings) {
    throw UnimplementedError('startMonitoring() has not been implemented.');
  }

  Future<void> stopMonitoring() {
    throw UnimplementedError('stopMonitoring() has not been implemented.');
  }

  // detect
  Future<bool> detectBeacon(BeaconRegion region) {
    throw UnimplementedError('detectBeacon() has not been implemented.');
  }

  // for background process
  Future<void> registerBackgroundCallback(
      int dispatcherHandle, int callbackHandle) {
    throw UnimplementedError(
        'registerBackgroundCallback() has not been implemented.');
  }

  /// stream event (enter/exit/ranged)
  Stream<BeaconEvent> get beaconEvents {
    throw UnimplementedError('beaconEvents has not been implemented.');
  }
}
