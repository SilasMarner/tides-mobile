// A planned fishing trip: a station, a date, an optional best-window alert,
// linked photos, and a weather/tide snapshot for the record. Mirrors
// CatchEntry's shape (plain immutable model + copyWith + JSON) so it fits the
// same StateNotifier-over-SharedPreferences persistence pattern.
class Trip {
  final String id;
  final String? nickname;
  final String stationId;
  final String stationName;
  final double lat;
  final double lon;
  final DateTime plannedDate; // date only; time-of-day is unused
  final bool alertEnabled;
  final int leadMinutes; // 15, 30, 45, or 60 — minutes before the best window
  final List<String> photoPaths;
  final String? notes;
  // A formatted snapshot of conditions/tide/best-window for plannedDate,
  // captured automatically after the trip is first saved (or refreshed by
  // hand afterward — see TripEntryScreen). Null until captured.
  final String? weatherSnapshot;
  final DateTime? weatherSnapshotAt;

  const Trip({
    required this.id,
    this.nickname,
    required this.stationId,
    required this.stationName,
    required this.lat,
    required this.lon,
    required this.plannedDate,
    this.alertEnabled = false,
    this.leadMinutes = 30,
    this.photoPaths = const [],
    this.notes,
    this.weatherSnapshot,
    this.weatherSnapshotAt,
  });

  Trip copyWith({
    String? nickname,
    String? stationId,
    String? stationName,
    double? lat,
    double? lon,
    DateTime? plannedDate,
    bool? alertEnabled,
    int? leadMinutes,
    List<String>? photoPaths,
    String? notes,
    String? weatherSnapshot,
    DateTime? weatherSnapshotAt,
    bool clearNickname = false,
    bool clearNotes = false,
  }) =>
      Trip(
        id: id,
        nickname: clearNickname ? null : (nickname ?? this.nickname),
        stationId: stationId ?? this.stationId,
        stationName: stationName ?? this.stationName,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        plannedDate: plannedDate ?? this.plannedDate,
        alertEnabled: alertEnabled ?? this.alertEnabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
        photoPaths: photoPaths ?? this.photoPaths,
        notes: clearNotes ? null : (notes ?? this.notes),
        weatherSnapshot: weatherSnapshot ?? this.weatherSnapshot,
        weatherSnapshotAt: weatherSnapshotAt ?? this.weatherSnapshotAt,
      );

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        nickname: j['nickname'] as String?,
        stationId: j['stationId'] as String,
        stationName: j['stationName'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        plannedDate: DateTime.parse(j['plannedDate'] as String),
        alertEnabled: j['alertEnabled'] as bool? ?? false,
        leadMinutes: j['leadMinutes'] as int? ?? 30,
        photoPaths:
            (j['photoPaths'] as List<dynamic>? ?? const []).cast<String>(),
        notes: j['notes'] as String?,
        weatherSnapshot: j['weatherSnapshot'] as String?,
        weatherSnapshotAt: j['weatherSnapshotAt'] != null
            ? DateTime.parse(j['weatherSnapshotAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'stationId': stationId,
        'stationName': stationName,
        'lat': lat,
        'lon': lon,
        'plannedDate': plannedDate.toIso8601String(),
        'alertEnabled': alertEnabled,
        'leadMinutes': leadMinutes,
        'photoPaths': photoPaths,
        'notes': notes,
        'weatherSnapshot': weatherSnapshot,
        'weatherSnapshotAt': weatherSnapshotAt?.toIso8601String(),
      };
}
