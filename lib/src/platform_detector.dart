import 'package:background_beacon_sdk/src/background_beacon_sdk_platform_interface.dart';
import 'package:flutter/foundation.dart';

enum MobilePlatform {
  ios,
  androidGms, // google services
  androidHms, // huawei services
  unsupported, // web/desktop or unknown mobile
}

class PlatformDetector {
  // const so the default instance can be shared everywhere
  const PlatformDetector();

  Future<MobilePlatform> detectPlatform() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return MobilePlatform.ios;
      case TargetPlatform.android:
        //check for hms or gms
        final services =
            await BackgroundBeaconPlatform.instance.detectMobileServices();
        return services == 'hms'
            ? MobilePlatform.androidHms
            : MobilePlatform.androidGms;
      default:
        return MobilePlatform.unsupported;
    }
  }
}
