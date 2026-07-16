class Beacon {
  final String uuid;
  final int major;
  final int minor;
  final int rssi;
  final int txPower;
  final double distance;
  final DateTime lastSeen;
  final String? mac;

  Beacon({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.rssi,
    required this.txPower,
    required this.distance,
    required this.lastSeen,
    this.mac,
  });

  factory Beacon.fromMap(Map<String, dynamic> json) {
    return Beacon(
        uuid: json['uuid'],
        major: json['major'],
        minor: json['minor'],
        rssi: json['rssi'],
        txPower: json['txPower'],
        distance: (json['distance'] as num).toDouble(),
        lastSeen: DateTime.parse(json['lastSeen']),
        mac: json['mac']);
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'rssi': rssi,
      'txPower': txPower,
      'distance': distance,
      'lastSeen': lastSeen.toIso8601String(),
      'mac': mac,
    };
  }
}
