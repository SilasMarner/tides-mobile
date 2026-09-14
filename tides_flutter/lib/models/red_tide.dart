// A single FWC water-sample reading for Karenia brevis (red tide), used by
// both the station Conditions-card advisory and the wind map's Red Tide
// layer. `count` is cells/liter; the category thresholds below match FWC's
// own published classification for this dataset.
class RedTideSample {
  final String location;
  final double lat;
  final double lon;
  final double count;
  final DateTime sampleDate;

  const RedTideSample({
    required this.location,
    required this.lat,
    required this.lon,
    required this.count,
    required this.sampleDate,
  });

  String get category {
    if (count > 1000000) return 'high';
    if (count > 100000) return 'medium';
    if (count > 10000) return 'low';
    if (count > 1000) return 'very low';
    return 'not present';
  }
}
