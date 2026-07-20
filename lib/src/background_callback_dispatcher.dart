import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:background_beacon_sdk/src/models/beacon_event.dart';

/// App-side callback invoked in the background isolate (Android only).
///
/// Must be a top-level function or static method — closures/instance
/// methods have no stable address for native to call back into
/// ([PluginUtilities.getCallbackHandle] returns null for them).
///
/// **If it does async work (API calls, posting notifications), declare it
/// `Future<void>` and await everything** — the dispatcher awaits this
/// callback to tell native the work truly finished before releasing the
/// process (fire-and-forget inside = the process may be reclaimed before
/// the notification appears).
///
/// Limits in this isolate: no UI/BuildContext, other plugins work only as
/// far as they support background isolates, and finish fast (the process
/// doesn't live long).
typedef BackgroundBeaconCallback = FutureOr<void> Function(BeaconEvent event);

/// Channel dedicated to the background isolate — separate from the main
/// channel (each isolate sets its own handler; they can't collide).
const MethodChannel _backgroundChannel =
    MethodChannel('background_beacon_sdk/background');

/// Entry point of the background isolate — native (HeadlessBeaconRunner)
/// runs this function via the callback handle stored during
/// registerBackgroundCallback.
///
/// `vm:entry-point` is required: nothing on the Dart side ever calls this
/// function, so without it AOT tree-shakes it away and native can't find
/// the callback.
///
/// Flow: native spins up the engine → runs the dispatcher → dispatcher sets
/// its handler and sends `backgroundReady` → native flushes queued events
/// through `onBeaconEvent` one at a time.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  // Let the app's other plugins work in this isolate (as far as they support it)
  DartPluginRegistrant.ensureInitialized();

  _backgroundChannel.setMethodCallHandler((call) async {
    if (call.method != 'onBeaconEvent') return;

    final args = Map<String, dynamic>.from(call.arguments as Map);
    final handle = CallbackHandle.fromRawHandle(args['callbackHandle'] as int);
    final callback = PluginUtilities.getCallbackFromHandle(handle);
    if (callback == null) {
      // The app was rebuilt and the old handle is stale — drop the event.
      // (Heals itself once the app opens and re-registers the callback.)
      return;
    }

    final event =
        BeaconEvent.fromMap(Map<String, dynamic>.from(args['event'] as Map));
    // Await fully before returning — native holds the goAsync window open
    // waiting on this handler's result; return too early and the process
    // dies before the app's work finishes.
    await (callback as BackgroundBeaconCallback)(event);
  });

  // Tell native the isolate is ready — events so far were queued native-side
  _backgroundChannel.invokeMethod<void>('backgroundReady');
}
