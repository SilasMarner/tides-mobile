// FWC's Karenia brevis (red tide) water-sample feed. Free, no key. Florida
// only -- the app has no equivalent source for the Texas/Gulf coast, so
// callers naturally see zero results outside Florida rather than an error.
import 'package:dio/dio.dart';
import '../models/red_tide.dart';

const _kBaseUrl = 'https://gis.myfwc.com/mapping/rest/services/Open_Data/'
    'Recent_Harmful_Algal_Bloom__HAB__Events_2024_present/MapServer/7/query';

final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)));

List<RedTideSample> _parseFeatures(List features) {
  final byLocation = <String, RedTideSample>{};
  for (final f in features) {
    final a = (f as Map)['attributes'] as Map;
    final lat = (a['LATITUDE'] as num?)?.toDouble();
    final lon = (a['LONGITUDE'] as num?)?.toDouble();
    final ms = (a['SAMPLE_DATE'] as num?)?.toInt();
    if (lat == null || lon == null || ms == null) continue;
    final location = (a['LOCATION'] as String?) ?? '$lat,$lon';
    final sample = RedTideSample(
      location: location,
      lat: lat,
      lon: lon,
      count: (a['COUNT_'] as num?)?.toDouble() ?? 0.0,
      sampleDate: DateTime.fromMillisecondsSinceEpoch(ms),
    );
    // Rows are ordered newest-first, so the first one seen per location wins.
    byLocation.putIfAbsent(location, () => sample);
  }
  return byLocation.values.toList();
}

/// Every sampling location inside the given lat/lon box with a sample in the
/// last [days] days, one (the latest) reading per location. Used by the wind
/// map's Red Tide layer.
Future<List<RedTideSample>> fetchRedTideInBounds(
  double latMin,
  double lonMin,
  double latMax,
  double lonMax, {
  int days = 21,
}) async {
  // SAMPLE_DATE is an esriFieldTypeDate column; this service's SQL layer
  // rejects a bare epoch-ms comparison (400 "Unable to complete operation")
  // and requires the TIMESTAMP literal form instead.
  final since = DateTime.now().subtract(Duration(days: days));
  final sinceLit = "TIMESTAMP '${since.year.toString().padLeft(4, '0')}-"
      "${since.month.toString().padLeft(2, '0')}-"
      "${since.day.toString().padLeft(2, '0')} 00:00:00'";
  final where = 'LATITUDE>=$latMin AND LATITUDE<=$latMax AND '
      'LONGITUDE>=$lonMin AND LONGITUDE<=$lonMax AND SAMPLE_DATE>=$sinceLit';
  final resp = await _dio.get(_kBaseUrl, queryParameters: {
    'where': where,
    'outFields': 'SAMPLE_DATE,LOCATION,LATITUDE,LONGITUDE,COUNT_',
    'orderByFields': 'SAMPLE_DATE DESC',
    'resultRecordCount': '500',
    'f': 'json',
  });
  final features = resp.data['features'] as List? ?? const [];
  return _parseFeatures(features);
}

/// The highest-count sample within roughly 10 miles of [lat]/[lon] in the
/// last [days] days, or null if nothing nearby (including everywhere outside
/// Florida). Used by the station Conditions-card advisory.
Future<RedTideSample?> fetchNearbyRedTide(
  double lat,
  double lon, {
  double radiusDeg = 0.15,
  int days = 14,
}) async {
  final samples = await fetchRedTideInBounds(
    lat - radiusDeg,
    lon - radiusDeg,
    lat + radiusDeg,
    lon + radiusDeg,
    days: days,
  );
  if (samples.isEmpty) return null;
  samples.sort((a, b) => b.count.compareTo(a.count));
  return samples.first;
}
