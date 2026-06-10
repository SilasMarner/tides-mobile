// Display-unit formatting helpers.
//
// All source data in the app is imperial (°F from NOAA, ft from the tide
// predictions and the marine API's `length_unit=imperial`, mph for wind).
// These helpers convert + format for display based on the user's units
// preference (see `unitsProvider`): `false` = Standard, `true` = Metric.

/// Temperature. Pass the value in °F. Returns e.g. "72.0°F" / "22.2°C".
String fmtTemp(double? f, bool metric, {int decimals = 1, String na = 'N/A'}) {
  if (f == null) return na;
  final v = metric ? (f - 32) * 5 / 9 : f;
  return '${v.toStringAsFixed(decimals)}${metric ? '°C' : '°F'}';
}

/// Integer temperature (NWS forecasts give whole degrees). Pass °F.
String fmtTempInt(int f, bool metric) {
  final v = metric ? ((f - 32) * 5 / 9).round() : f;
  return '$v${metric ? '°C' : '°F'}';
}

/// Temperature *difference* (anomaly/delta). Pass the value in °C — deltas
/// scale by 1.8 with no +32 offset, so `fmtTemp` would be wrong here.
String fmtTempDelta(double c, bool metric, {int decimals = 1}) {
  final v = metric ? c : c * 1.8;
  return '${v.toStringAsFixed(decimals)}${metric ? '°C' : '°F'}';
}

/// A length such as water level or wave height. Pass the value in feet.
String fmtLen(double? ft, bool metric, {int decimals = 1, String na = 'N/A'}) {
  if (ft == null) return na;
  final v = metric ? ft * 0.3048 : ft;
  return '${v.toStringAsFixed(decimals)} ${metric ? 'm' : 'ft'}';
}

/// Tide height with an explicit +/- sign. Pass the value in feet.
String fmtTideHeight(double ft, bool metric) {
  final v = metric ? ft * 0.3048 : ft;
  return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} ${metric ? 'm' : 'ft'}';
}

/// Wind speed. Pass the value in mph.
String fmtSpeed(double mph, bool metric, {int decimals = 0}) {
  final v = metric ? mph * 1.60934 : mph;
  return '${v.toStringAsFixed(decimals)} ${metric ? 'km/h' : 'mph'}';
}

/// Convert a free-text NWS wind string ("10 mph", "7 to 12 mph") to metric,
/// replacing the numbers with their km/h equivalents. Returns the input
/// unchanged in Standard mode.
String fmtWindString(String s, bool metric) {
  if (!metric || s.isEmpty) return s;
  final converted = s.replaceAllMapped(
    RegExp(r'\d+'),
    (m) => (int.parse(m[0]!) * 1.60934).round().toString(),
  );
  return converted.replaceAll('mph', 'km/h');
}
