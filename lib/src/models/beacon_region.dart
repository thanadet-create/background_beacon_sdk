class BeaconRegion {
  final String identifier;
  final String? uuid;
  final int? major;
  final int? minor;

  BeaconRegion({
    required this.identifier,
    String? uuid,
    this.major,
    this.minor,
  })  : assert(uuid != null || major == null,
            'major/minor require uuid (wildcard region matches everything)'),
        assert(minor == null || major != null, 'minor requires major'),
        uuid = uuid?.toLowerCase();

  factory BeaconRegion.fromMap(Map<String, dynamic> json) {
    return BeaconRegion(
        identifier: json['identifier'],
        uuid: json['uuid'],
        major: json['major'],
        minor: json['minor']);
  }

  Map<String, dynamic> toMap() {
    return {
      'identifier': identifier,
      'uuid': uuid,
      'major': major,
      'minor': minor,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is BeaconRegion &&
      other.identifier == identifier &&
      other.uuid == uuid &&
      other.major == major &&
      other.minor == minor;

  @override
  int get hashCode => Object.hash(identifier, uuid, major, minor);
}
