/// An SDK for receiving BLE beacon signals while running in the background.
///
/// Automatically detects and supports iOS, Android (GMS), and Huawei (HMS) platforms.
///
/// **Usage Guidelines:**
/// * The application should import **only this single file**. Everything exported from this file constitutes the Public API.
/// * Any components located within `src/` that are not explicitly exported are considered internal and subject to change without notice.
///
/// **Main Entry Point:**
/// The primary class for interaction is `BeaconManager`
/// The typical lifecycle flow is:
/// `initialize` ➔ `requestPermissions` ➔ `startMonitoring` ➔ Listen to the event stream.

library background_beacon_sdk;

export 'src/background_callback_dispatcher.dart' show BackgroundBeaconCallback;
export 'src/beacon_manager.dart';
export 'src/models/beacon.dart';
export 'src/models/beacon_event.dart';
export 'src/models/beacon_region.dart';
export 'src/models/scan_settings.dart';
export 'src/platform_detector.dart';
