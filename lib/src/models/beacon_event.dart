import 'package:background_beacon_sdk/src/models/beacon.dart';

enum BeaconEventType {
  enterRegion,
  exitRegion,
  ranged,

  /// User paused scanning from the foreground service notification
  /// (Android FGS mode only). `region` is empty and `beacons` is empty —
  /// the event is about the whole session, not one region. Scanning stays
  /// off until [monitoringResumed]; no enter/exit/ranged events in between.
  monitoringPaused,

  /// User resumed scanning from the notification (Android FGS mode only).
  /// Region state restarts fresh: beacons still in range re-fire
  /// `enterRegion` once (same semantics as a headless restart).
  monitoringResumed,
}

class BeaconEvent {
  final BeaconEventType type;
  final String region;
  final List<Beacon> beacons;
  final DateTime timestamp;

  BeaconEvent({
    required this.type,
    required this.region,
    required this.beacons,
    required this.timestamp,
  });

  factory BeaconEvent.fromMap(Map<String, dynamic> json) {
    return BeaconEvent(
        type: BeaconEventType.values.byName(json['type']),
        region: json['region'],
        beacons: (json['beacons'] as List)
            .map((e) => Beacon.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        timestamp: DateTime.parse(json['timestamp']));
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'region': region,
      'beacons': beacons.map((b) => b.toMap()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
