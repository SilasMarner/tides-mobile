class Station {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final double? dist;

  const Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.dist,
  });

  factory Station.fromJson(Map<String, dynamic> j, {double? dist}) => Station(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        dist: dist,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
      };

  @override
  bool operator ==(Object other) => other is Station && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
