class CatchEntry {
  final String id;
  final String species;
  final DateTime caughtAt;
  final double? lengthIn;
  final double? girthIn;
  final double? weightLb;
  final bool released;
  final double? lat;
  final double? lon;
  final String? locationLabel;
  final String? photoPath;
  final String? tournamentId;
  final String? notes;
  final double? forkLengthIn;
  final String? tagNumber;
  final String? dnaSampleNumber;
  final String? sex;
  final bool isRecapture;
  final String? recaptureTagNumber;
  final DateTime? releasedAt;

  const CatchEntry({
    required this.id,
    required this.species,
    required this.caughtAt,
    this.lengthIn,
    this.girthIn,
    this.weightLb,
    this.released = false,
    this.lat,
    this.lon,
    this.locationLabel,
    this.photoPath,
    this.tournamentId,
    this.notes,
    this.forkLengthIn,
    this.tagNumber,
    this.dnaSampleNumber,
    this.sex,
    this.isRecapture = false,
    this.recaptureTagNumber,
    this.releasedAt,
  });

  CatchEntry copyWith({
    String? species,
    DateTime? caughtAt,
    double? lengthIn,
    double? girthIn,
    double? weightLb,
    bool? released,
    double? lat,
    double? lon,
    String? locationLabel,
    String? photoPath,
    String? tournamentId,
    String? notes,
    double? forkLengthIn,
    String? tagNumber,
    String? dnaSampleNumber,
    String? sex,
    bool? isRecapture,
    String? recaptureTagNumber,
    DateTime? releasedAt,
    bool clearLengthIn = false,
    bool clearGirthIn = false,
    bool clearWeightLb = false,
    bool clearLatLon = false,
    bool clearLocationLabel = false,
    bool clearPhotoPath = false,
    bool clearTournamentId = false,
    bool clearNotes = false,
    bool clearForkLengthIn = false,
    bool clearTagNumber = false,
    bool clearDnaSampleNumber = false,
    bool clearSex = false,
    bool clearRecaptureTagNumber = false,
    bool clearReleasedAt = false,
  }) =>
      CatchEntry(
        id: id,
        species: species ?? this.species,
        caughtAt: caughtAt ?? this.caughtAt,
        lengthIn: clearLengthIn ? null : (lengthIn ?? this.lengthIn),
        girthIn: clearGirthIn ? null : (girthIn ?? this.girthIn),
        weightLb: clearWeightLb ? null : (weightLb ?? this.weightLb),
        released: released ?? this.released,
        lat: clearLatLon ? null : (lat ?? this.lat),
        lon: clearLatLon ? null : (lon ?? this.lon),
        locationLabel: clearLocationLabel
            ? null
            : (locationLabel ?? this.locationLabel),
        photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
        tournamentId:
            clearTournamentId ? null : (tournamentId ?? this.tournamentId),
        notes: clearNotes ? null : (notes ?? this.notes),
        forkLengthIn:
            clearForkLengthIn ? null : (forkLengthIn ?? this.forkLengthIn),
        tagNumber: clearTagNumber ? null : (tagNumber ?? this.tagNumber),
        dnaSampleNumber: clearDnaSampleNumber
            ? null
            : (dnaSampleNumber ?? this.dnaSampleNumber),
        sex: clearSex ? null : (sex ?? this.sex),
        isRecapture: isRecapture ?? this.isRecapture,
        recaptureTagNumber: clearRecaptureTagNumber
            ? null
            : (recaptureTagNumber ?? this.recaptureTagNumber),
        releasedAt: clearReleasedAt ? null : (releasedAt ?? this.releasedAt),
      );

  factory CatchEntry.fromJson(Map<String, dynamic> j) => CatchEntry(
        id: j['id'] as String,
        species: j['species'] as String,
        caughtAt: DateTime.parse(j['caughtAt'] as String),
        lengthIn: (j['lengthIn'] as num?)?.toDouble(),
        girthIn: (j['girthIn'] as num?)?.toDouble(),
        weightLb: (j['weightLb'] as num?)?.toDouble(),
        released: j['released'] as bool? ?? false,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        locationLabel: j['locationLabel'] as String?,
        photoPath: j['photoPath'] as String?,
        tournamentId: j['tournamentId'] as String?,
        notes: j['notes'] as String?,
        forkLengthIn: (j['forkLengthIn'] as num?)?.toDouble(),
        tagNumber: j['tagNumber'] as String?,
        dnaSampleNumber: j['dnaSampleNumber'] as String?,
        sex: j['sex'] as String?,
        isRecapture: j['isRecapture'] as bool? ?? false,
        recaptureTagNumber: j['recaptureTagNumber'] as String?,
        releasedAt: j['releasedAt'] != null
            ? DateTime.parse(j['releasedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'species': species,
        'caughtAt': caughtAt.toIso8601String(),
        'lengthIn': lengthIn,
        'girthIn': girthIn,
        'weightLb': weightLb,
        'released': released,
        'lat': lat,
        'lon': lon,
        'locationLabel': locationLabel,
        'photoPath': photoPath,
        'tournamentId': tournamentId,
        'notes': notes,
        'forkLengthIn': forkLengthIn,
        'tagNumber': tagNumber,
        'dnaSampleNumber': dnaSampleNumber,
        'sex': sex,
        'isRecapture': isRecapture,
        'recaptureTagNumber': recaptureTagNumber,
        'releasedAt': releasedAt?.toIso8601String(),
      };
}
