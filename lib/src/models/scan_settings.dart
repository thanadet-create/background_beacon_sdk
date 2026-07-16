class ScanSettings {
  final int scanIntervalMs;
  final int scanDurationMs;
  final bool foregroundServiceNotification;
  final String beaconLayout;
  final bool rangingEnabled;
  final bool continuousRanging;

  ScanSettings({
    required this.scanIntervalMs,
    required this.scanDurationMs,
    required this.foregroundServiceNotification,
    required this.beaconLayout,
    required this.rangingEnabled,
    this.continuousRanging = false,
  });

  factory ScanSettings.fromMap(Map<String, dynamic> json) {
    return ScanSettings(
        scanIntervalMs: json['scanIntervalMs'],
        scanDurationMs: json['scanDurationMs'],
        foregroundServiceNotification: json['foregroundServiceNotification'],
        beaconLayout: json['beaconLayout'],
        rangingEnabled: json['rangingEnabled'],
        continuousRanging: json['continuousRanging'] ?? false);
  }

  Map<String, dynamic> toMap() {
    return {
      'scanIntervalMs': scanIntervalMs,
      'scanDurationMs': scanDurationMs,
      'foregroundServiceNotification': foregroundServiceNotification,
      'beaconLayout': beaconLayout,
      'rangingEnabled': rangingEnabled,
      'continuousRanging': continuousRanging,
    };
  }
}
