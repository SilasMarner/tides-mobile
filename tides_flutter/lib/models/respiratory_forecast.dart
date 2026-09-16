// A beach-level Karenia brevis (red tide) respiratory-irritation forecast
// point from NOAA NCCOS's Gulf Coast forecast service. Unlike FwcApi's raw
// water samples, this is forward-looking: a risk category per 3-hour slot
// out to ~30 hours, driven by cell counts plus forecast wind. Covers both
// Florida and Texas beaches (sparsely — a few dozen stations Gulf-wide), so
// it's the only red-tide source in this app with any Texas coverage.
class RespiratoryForecastSample {
  final String locationName;
  final double lat;
  final double lon;
  final String category; // e.g. "Very low", "Moderate", "High"
  final DateTime forecastTime; // UTC
  final double confidence; // 0.0-1.0

  const RespiratoryForecastSample({
    required this.locationName,
    required this.lat,
    required this.lon,
    required this.category,
    required this.forecastTime,
    required this.confidence,
  });

  /// FWC/NCCOS only flag "Moderate" and "High" as a real heads-up; "Very
  /// low"/"Low"/"None" are background levels not worth surfacing.
  bool get isAdvisory {
    final c = category.toLowerCase();
    return c != 'none' && c != 'very low' && c != 'low';
  }
}
