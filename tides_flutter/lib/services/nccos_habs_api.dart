// NOAA NCCOS's Gulf Coast Red Tide Respiratory Forecast feed. Free, no key.
// Traced out of the ArcGIS Experience Builder app at
// https://experience.arcgis.com/experience/1ef2c961393948f3861d5ec9831250ee
// (not linked anywhere on the NCCOS site itself) -- this is the underlying
// hosted feature service it reads from. Sparse (~30 beach points Gulf-wide)
// but, unlike FwcApi, covers Texas as well as Florida.
import 'dart:math' as math;
import 'package:dio/dio.dart';
import '../models/respiratory_forecast.dart';

const _kBaseUrl = 'https://services2.arcgis.com/C8EMgrsFcRFL6LrL/arcgis/'
    'rest/services/nccos_habs_stations/FeatureServer/0/query';

// Forecast slots are lettered A-J, one per 3-hour step out to ~30 hours.
const _kSlots = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];

final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)));

double _milesBetween(double lat1, double lon1, double lat2, double lon2) {
  const rMiles = 3958.8;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLon = (lon2 - lon1) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.asin(math.sqrt(a));
  return rMiles * c;
}

/// The nearest forecast station within [radiusMiles] of [lat]/[lon], carrying
/// whichever of its 10 forecast slots is soonest in the future (or the last
/// one, if the whole window has already passed). Null if nothing nearby --
/// this feed only has ~30 stations Gulf-wide, so most tide stations will see
/// null and that's expected, not an error.
Future<RespiratoryForecastSample?> fetchNearbyRespiratoryForecast(
  double lat,
  double lon, {
  double radiusMiles = 25,
}) async {
  // Coarse bounding box in degrees, then a real distance check client-side --
  // cheaper than an ArcGIS spatial (distance) query for a feed this small.
  final degPad = radiusMiles / 55; // ~55 miles/degree at this latitude
  final where = 'Lat>=${lat - degPad} AND Lat<=${lat + degPad} AND '
      'Lon>=${lon - degPad} AND Lon<=${lon + degPad}';
  final outFields = [
    'LocationName',
    'Lat',
    'Lon',
    for (final s in _kSlots) ...['Forecast_$s', 'WindTime_$s', 'Confidence_$s']
  ].join(',');
  final resp = await _dio.get(_kBaseUrl, queryParameters: {
    'where': where,
    'outFields': outFields,
    'f': 'json',
  });
  final features = resp.data['features'] as List? ?? const [];
  if (features.isEmpty) return null;

  RespiratoryForecastSample? best;
  double bestMiles = double.infinity;
  final now = DateTime.now().toUtc();
  for (final f in features) {
    final a = (f as Map)['attributes'] as Map;
    final sLat = (a['Lat'] as num?)?.toDouble();
    final sLon = (a['Lon'] as num?)?.toDouble();
    if (sLat == null || sLon == null) continue;
    final miles = _milesBetween(lat, lon, sLat, sLon);
    if (miles > radiusMiles || miles >= bestMiles) continue;

    final sample = _nextSlot(a, sLat, sLon, now);
    if (sample == null) continue;
    best = sample;
    bestMiles = miles;
  }
  return best;
}

RespiratoryForecastSample? _nextSlot(
    Map a, double lat, double lon, DateTime now) {
  final name = (a['LocationName'] as String?) ?? '$lat,$lon';
  RespiratoryForecastSample? firstFuture;
  RespiratoryForecastSample? last;
  for (final s in _kSlots) {
    final cat = a['Forecast_$s'] as String?;
    final ms = a['WindTime_$s'];
    final confidence = (a['Confidence_$s'] as num?)?.toDouble() ?? 0.0;
    if (cat == null || ms == null) continue;
    final time = DateTime.parse(ms is String ? ms : ms.toString()).toUtc();
    final sample = RespiratoryForecastSample(
      locationName: name,
      lat: lat,
      lon: lon,
      category: cat,
      forecastTime: time,
      confidence: confidence,
    );
    last = sample;
    if (firstFuture == null && time.isAfter(now)) firstFuture = sample;
  }
  return firstFuture ?? last;
}
