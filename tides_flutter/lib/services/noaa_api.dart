import 'dart:math';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
export '../models/tide_data.dart' show WaveData;

final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)));
final _dateFmt = DateFormat('yyyyMMdd');
final _timeFmt = DateFormat('yyyy-MM-dd HH:mm');

const _stationsUrl =
    'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json'
    '?type=tidepredictions&units=english';

// ── Helpers ───────────────────────────────────────────────────────────────────

double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 3959.0;
  final dlat = _rad(lat2 - lat1);
  final dlon = _rad(lon2 - lon1);
  final a = pow(sin(dlat / 2), 2) +
      cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dlon / 2), 2);
  return r * 2 * asin(sqrt(max(0, min(1, a as double))));
}

double _rad(double d) => d * pi / 180;

String windDirArrow(double degrees) {
  const dirs = [
    'N','NNE','NE','ENE','E','ESE','SE','SSE',
    'S','SSW','SW','WSW','W','WNW','NW','NNW'
  ];
  return dirs[(degrees / 22.5).round() % 16];
}

String beaufort(double mph) {
  if (mph < 1) return 'Calm';
  if (mph < 4) return 'Light air';
  if (mph < 8) return 'Light breeze';
  if (mph < 13) return 'Gentle breeze';
  if (mph < 19) return 'Moderate breeze';
  if (mph < 25) return 'Fresh breeze';
  if (mph < 32) return 'Strong breeze';
  return 'Near gale+';
}

String fmtHhmm(double decimalHours) {
  final h = decimalHours % 24;
  final hh = h.floor();
  final mm = ((h - hh) * 60).round();
  final hh12 = hh % 12 == 0 ? 12 : hh % 12;
  final suffix = hh < 12 ? 'AM' : 'PM';
  return '$hh12:${mm.toString().padLeft(2, '0')} $suffix';
}

// ── Sun / Moon / Solunar (ported from Python) ─────────────────────────────────

double _julianDate(DateTime d) {
  var y = d.year;
  var m = d.month;
  final day = d.day;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = y ~/ 100;
  final b = 2 - a + a ~/ 4;
  return (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      day +
      b -
      1524.5;
}

MoonInfo moonPhase(DateTime d) {
  final days = (_julianDate(d) - 2451549.5) % 29.53058867;
  final illum = ((1 - cos(2 * pi * days / 29.53058867)) / 2 * 100).round();
  final p = days / 29.53058867;
  String phase;
  if (p < 0.0625 || p >= 0.9375) {
    phase = 'New Moon';
  } else if (p < 0.1875) {
    phase = 'Waxing Crescent';
  } else if (p < 0.3125) {
    phase = 'First Quarter';
  } else if (p < 0.4375) {
    phase = 'Waxing Gibbous';
  } else if (p < 0.5625) {
    phase = 'Full Moon';
  } else if (p < 0.6875) {
    phase = 'Waning Gibbous';
  } else if (p < 0.8125) {
    phase = 'Last Quarter';
  } else {
    phase = 'Waning Crescent';
  }
  return MoonInfo(phase: phase, pct: illum);
}

SunInfo sunTimes(DateTime d, double lat, double lon, double utcOff) {
  final n = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
  final declR = _rad(-23.45 * cos(_rad(360 / 365 * (n + 10))));
  final b = _rad(360 / 364 * (n - 81));
  final eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b);
  final noonUtc = 12.0 - lon / 15.0 - eot / 60.0;
  final cosHa = -tan(_rad(lat)) * tan(declR);
  if (cosHa <= -1 || cosHa >= 1) {
    return SunInfo(
      sunrise: 'N/A',
      sunset: 'N/A',
      noon: fmtHhmm(noonUtc + utcOff),
      golden: 'N/A',
    );
  }
  final haH = (acos(cosHa) * 180 / pi) / 15.0;
  final sunrise = noonUtc - haH + utcOff;
  final sunset = noonUtc + haH + utcOff;
  return SunInfo(
    sunrise: fmtHhmm(sunrise),
    sunset: fmtHhmm(sunset),
    noon: fmtHhmm(noonUtc + utcOff),
    golden: fmtHhmm(sunset - 1.0),
  );
}

double _moonRa(double jd) {
  final dv = jd - 2451545.0;
  final l = (218.316 + 13.176396 * dv) % 360;
  final m = _rad((134.963 + 13.064993 * dv) % 360);
  final f = _rad((93.272 + 13.229350 * dv) % 360);
  final lam = (l +
          6.289 * sin(m) -
          1.274 * sin(2 * _rad(l) - m) +
          0.658 * sin(2 * _rad(l)) -
          0.214 * sin(2 * m) -
          0.114 * sin(2 * f)) %
      360;
  final beta = 5.128 * sin(f);
  final eps = _rad(23.439 - 0.0000004 * dv);
  final lr = _rad(lam);
  final br = _rad(beta);
  final x = cos(br) * cos(lr);
  final y = cos(eps) * cos(br) * sin(lr) - sin(eps) * sin(br);
  return (atan2(y, x) * 180 / pi) % 360;
}

SolunarInfo solunarTimes(DateTime d, double lon, double utcOff) {
  final jd0 = _julianDate(d);
  final t = (jd0 - 2451545.0) / 36525.0;
  final gmst0 = (100.4606184 + 36000.77004 * t + 0.000387933 * t * t) % 360;
  var ra = _moonRa(jd0 + 0.5);
  var tUt = ((ra - lon - gmst0) % 360) / (360.985647 / 24);
  ra = _moonRa(jd0 + tUt / 24);
  tUt = ((ra - lon - gmst0) % 360) / (360.985647 / 24);
  final upper = (tUt + utcOff) % 24;
  final lower = (upper + 12 + 25 / 60) % 24;
  final minor1 = (upper - 6 - 12.5 / 60) % 24;
  final minor2 = (upper + 6 + 12.5 / 60) % 24;
  return SolunarInfo(major1: upper, major2: lower, minor1: minor1, minor2: minor2);
}

double _centralUtcOffset(DateTime d) {
  final y = d.year;
  final dstStart = List.generate(7, (i) => DateTime(y, 3, 8 + i))
      .firstWhere((dt) => dt.weekday == DateTime.sunday);
  final dstEnd = List.generate(7, (i) => DateTime(y, 11, 1 + i))
      .firstWhere((dt) => dt.weekday == DateTime.sunday);
  final dateOnly = DateTime(d.year, d.month, d.day);
  return (dateOnly.isAfter(dstStart.subtract(const Duration(days: 1))) &&
          dateOnly.isBefore(dstEnd))
      ? -5.0
      : -6.0;
}

FishingInfo fishingRating(
    List<TidePrediction> hilo, double? windMph, SolunarInfo sol) {
  final now = DateTime.now();
  final nowH = now.hour + now.minute / 60;
  var score = 0;

  for (final p in hilo) {
    final diff = ((p.time.hour + p.time.minute / 60) - nowH).abs();
    if (diff < 1.5) {
      score += 2;
      break;
    } else if (diff < 3.0) {
      score += 1;
      break;
    }
  }

  if (windMph != null) {
    if (windMph < 10) {
      score += 2;
    } else if (windMph < 15) {
      score += 1;
    }
  }

  bool inPeriod(double start, double dur) {
    final end = (start + dur) % 24;
    return start < end
        ? nowH >= start && nowH < end
        : nowH >= start || nowH < end;
  }

  if (inPeriod(sol.major1, 2) || inPeriod(sol.major2, 2)) {
    score += 2;
  } else if (inPeriod(sol.minor1, 1) || inPeriod(sol.minor2, 1)) {
    score += 1;
  }

  final clamped = min(score, 5);
  final label = {5: 'Excellent', 4: 'Very Good', 3: 'Good', 2: 'Fair'}[clamped] ?? 'Poor';
  return FishingInfo(stars: clamped, label: label);
}

// ── API calls ──────────────────────────────────────────────────────────────────

Future<dynamic> apiGet(String url, {Map<String, String>? headers}) async {
  try {
    final resp = await _dio.get<dynamic>(url,
        options: Options(headers: headers, receiveTimeout: const Duration(seconds: 15)));
    return resp.data;
  } catch (_) {
    return null;
  }
}

Future<String?> _fetchText(String url) async {
  try {
    final resp = await _dio.get<String>(url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
        ));
    return resp.data;
  } catch (_) {
    return null;
  }
}

// ── NDBC wave data ────────────────────────────────────────────────────────────

DateTime? _ndbcObsTime;
List<List<String>>? _ndbcObsCache;

Future<List<List<String>>> _fetchNdbcObs() async {
  final now = DateTime.now();
  if (_ndbcObsCache != null &&
      _ndbcObsTime != null &&
      now.difference(_ndbcObsTime!).inMinutes < 30) {
    return _ndbcObsCache!;
  }
  final text = await _fetchText(
      'https://www.ndbc.noaa.gov/data/latest_obs/latest_obs.txt');
  if (text == null) return [];
  final rows = text
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .map((l) => l.trim().split(RegExp(r'\s+')))
      .toList();
  _ndbcObsCache = rows;
  _ndbcObsTime = now;
  return rows;
}

double? _mm(String s) => s == 'MM' ? null : double.tryParse(s);

Future<WaveData?> fetchNdbcWaves(double lat, double lon) async {
  // latest_obs.txt columns: 0=STN 1=LAT 2=LON ... 11=WVHT 12=DPD 13=APD 14=MWD
  final rows = await _fetchNdbcObs();
  String? bestId;
  double? bestWvht, bestDpd, bestMwd;
  double bestDist = 150;

  for (final row in rows) {
    if (row.length < 15) continue;
    final rLat = double.tryParse(row[1]);
    final rLon = double.tryParse(row[2]);
    if (rLat == null || rLon == null) continue;
    final wvht = _mm(row[11]);
    if (wvht == null) continue;
    final d = haversine(lat, lon, rLat, rLon);
    if (d < bestDist) {
      bestDist = d;
      bestId = row[0];
      bestWvht = wvht;
      bestDpd = _mm(row[12]);
      bestMwd = _mm(row[14]);
    }
  }
  if (bestId == null || bestWvht == null) return null;

  // .spec actual columns: 0=YY 1=MM 2=DD 3=hh 4=mm 5=WVHT 6=SwH 7=SwP 8=WWH 9=WWP 10=SwD 11=WWD
  // SwD is a compass string (e.g. "ESE"), WWD is degrees true
  double? swh, swp, wwh, wwp;
  String? swdStr;
  final spec = await _fetchText(
      'https://www.ndbc.noaa.gov/data/realtime2/$bestId.spec');
  if (spec != null) {
    final lines = spec
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    if (lines.isNotEmpty) {
      final p = lines[0].trim().split(RegExp(r'\s+'));
      if (p.length >= 12) {
        swh = _mm(p[6]);
        swp = _mm(p[7]);
        wwh = _mm(p[8]);
        wwp = _mm(p[9]);
        swdStr = (p[10] == 'MM') ? null : p[10];
      }
    }
  }

  const mToFt = 3.28084;
  return WaveData(
    waveHeight: bestWvht * mToFt,
    domPeriod: bestDpd ?? 0,
    waveDir: bestMwd != null ? windDirArrow(bestMwd) : null,
    swellHeight: swh != null ? swh * mToFt : null,
    swellPeriod: swp,
    swellDir: swdStr,
    windWaveHeight: wwh != null ? wwh * mToFt : null,
    windWavePeriod: wwp,
    ndbcStation: bestId,
    distance: bestDist,
  );
}

// ── Station capability map ────────────────────────────────────────────────────
//
// NOAA mdapi valid type= values that return station lists:
//   type=waterlevels → 301 stations with live water-level sensors  → wl
//   type=met         → 318 stations with met sensors (wind/at/pres) → wind, at, pres
//   type=physocean   → 240 stations with physical oceanography      → wt, sal
//
// The legacy keys (type=wind, type=salinity, etc.) return 0 stations.

Future<Map<String, Set<String>>> fetchCapabilityMap() async {
  const base =
      'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=';

  // Fetch the three valid type lists in parallel
  final results = await Future.wait([
    apiGet('${base}waterlevels'),
    apiGet('${base}met'),
    apiGet('${base}physocean'),
  ]);

  Set<String> ids(dynamic data) =>
      (data?['stations'] as List? ?? [])
          .map<String>((s) => s['id'] as String)
          .toSet();

  final wlIds      = ids(results[0]);
  final metIds     = ids(results[1]);
  final physIds    = ids(results[2]);

  final map = <String, Set<String>>{};

  void add(String id, String cap) =>
      map.putIfAbsent(id, () => {}).add(cap);

  for (final id in wlIds)   { add(id, 'wl'); }
  for (final id in metIds)  { add(id, 'wind'); add(id, 'at'); add(id, 'pres'); }
  for (final id in physIds) { add(id, 'wt');   add(id, 'sal'); }

  return map;
}

Future<List<Station>> searchStations(String query) async {
  final data = await apiGet(_stationsUrl);
  if (data == null || data['stations'] == null) return [];
  final q = query.toLowerCase();
  final results = <Station>[];
  for (final s in data['stations'] as List) {
    final name = (s['name'] as String? ?? '').toLowerCase();
    final state = (s['state'] as String? ?? '').toLowerCase();
    if (name.contains(q) || state.contains(q)) {
      final stateStr = s['state'] as String? ?? '';
      final nameStr = s['name'] as String? ?? '';
      results.add(Station(
        id: s['id'] as String,
        name: stateStr.isNotEmpty ? '$nameStr, $stateStr' : nameStr,
        lat: double.tryParse(s['lat'].toString()) ?? 0,
        lon: double.tryParse(s['lng'].toString()) ?? 0,
      ));
    }
  }
  return results;
}

Future<List<Station>> nearestStations(double lat, double lon, {int n = 6}) async {
  final data = await apiGet(_stationsUrl);
  if (data == null || data['stations'] == null) return [];
  final results = <Station>[];
  for (final s in data['stations'] as List) {
    try {
      final slat = double.parse(s['lat'].toString());
      final slon = double.parse(s['lng'].toString());
      final stateStr = s['state'] as String? ?? '';
      final nameStr = s['name'] as String? ?? '';
      results.add(Station(
        id: s['id'] as String,
        name: stateStr.isNotEmpty ? '$nameStr, $stateStr' : nameStr,
        lat: slat,
        lon: slon,
        dist: haversine(lat, lon, slat, slon),
      ));
    } catch (_) {}
  }
  results.sort((a, b) => (a.dist ?? 0).compareTo(b.dist ?? 0));
  return results.take(n).toList();
}

Future<List<TidePrediction>> _fetchPredictions(
    String stationId, String dateStr, String interval) async {
  final url = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter'
      '?begin_date=$dateStr&end_date=$dateStr'
      '&station=$stationId'
      '&product=predictions&datum=MLLW&time_zone=lst_ldt'
      '&interval=$interval&units=english&format=json&application=tides_flutter';
  final data = await apiGet(url);
  return _parsePredictions((data?['predictions'] as List?) ?? []);
}

List<TidePrediction> _parsePredictions(List raw) {
  final out = <TidePrediction>[];
  for (final p in raw) {
    try {
      final t = _timeFmt.parse(p['t'] as String);
      final v = double.parse(p['v'] as String);
      out.add(TidePrediction(time: t, height: v, type: p['type'] as String?));
    } catch (_) {}
  }
  return out;
}

Future<dynamic> _fetchObs(String stationId, String product) async {
  final url = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter'
      '?station=$stationId&product=$product'
      '&date=latest&units=english&time_zone=lst_ldt&format=json';
  final data = await apiGet(url);
  if (data == null || data['data'] == null) return null;
  final list = data['data'] as List;
  return list.isNotEmpty ? list.last : null;
}

Future<int> _fetchPressureTrend(String stationId) async {
  final url = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter'
      '?station=$stationId&product=air_pressure'
      '&range=3&units=english&time_zone=lst_ldt&format=json';
  final data = await apiGet(url);
  if (data == null || data['data'] == null) return 0;
  final pts = data['data'] as List;
  if (pts.length < 2) return 0;
  try {
    final diff = double.parse(pts.last['v'].toString()) -
        double.parse(pts.first['v'].toString());
    return diff > 0.5 ? 1 : diff < -0.5 ? -1 : 0;
  } catch (_) {
    return 0;
  }
}

Future<dynamic> _fetchWaterLevel(String stationId) async {
  final url = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter'
      '?station=$stationId&product=water_level&datum=MLLW'
      '&date=latest&units=english&time_zone=lst_ldt&format=json';
  final data = await apiGet(url);
  if (data == null || data['data'] == null) return null;
  final list = data['data'] as List;
  return list.isNotEmpty ? list.last : null;
}

Future<Map<String, dynamic>?> _fetchNws(double lat, double lon) async {
  const hdr = {'User-Agent': 'tides-flutter/2.0'};
  // Many coastal/offshore stations sit on water where NWS has no grid data.
  // Try the exact coords first, then small offsets to find a valid land grid point.
  const offsets = [
    [0.0, 0.0], [0.06, 0.0], [-0.06, 0.0],
    [0.0, 0.06], [0.0, -0.06], [0.06, 0.06], [-0.06, -0.06],
  ];
  for (final off in offsets) {
    final result = await _tryNwsFetch(lat + off[0], lon + off[1], hdr);
    if (result != null) return result;
  }
  return null;
}

Future<Map<String, dynamic>?> _tryNwsFetch(
    double lat, double lon, Map<String, String> hdr) async {
  final pts = await apiGet('https://api.weather.gov/points/$lat,$lon', headers: hdr);
  if (pts == null) return null;
  final props = pts['properties'] as Map<String, dynamic>? ?? {};
  final hourlyUrl = props['forecastHourly'] as String?;
  final forecastUrl = props['forecast'] as String?;
  final result = <String, dynamic>{};
  if (hourlyUrl != null) {
    final hly = await apiGet(hourlyUrl, headers: hdr);
    if (hly != null) {
      result['hourly'] =
          ((hly['properties']['periods'] as List?)?.take(3).toList()) ?? [];
    }
  }
  if (forecastUrl != null) {
    final fc = await apiGet(forecastUrl, headers: hdr);
    if (fc != null) {
      result['forecast'] = fc['properties']['periods'] as List? ?? [];
    }
  }
  return result.isEmpty ? null : result;
}

Conditions _parseConditions(Map<String, dynamic?> obs, int pressureTrend) {
  double? tryParse(dynamic val) {
    if (val == null) return null;
    return double.tryParse(val.toString());
  }

  final air = obs['air_temperature'];
  final wind = obs['wind'];
  final pres = obs['air_pressure'];
  final water = obs['water_temperature'];
  final wlev = obs['water_level'];
  final sal = obs['salinity'];

  double? windSpeed, windDir, windGust;
  String? windDirStr, beaufortStr;
  if (wind != null) {
    windSpeed = tryParse(wind['s']);
    windDir = tryParse(wind['d']);
    windGust = tryParse(wind['g']);
    if (windDir != null) windDirStr = windDirArrow(windDir);
    if (windSpeed != null) beaufortStr = beaufort(windSpeed);
  }

  return Conditions(
    airTemp: tryParse(air?['v']),
    waterTemp: tryParse(water?['v']),
    windSpeed: windSpeed,
    windDir: windDir,
    windGust: windGust,
    windDirStr: windDirStr,
    beaufortStr: beaufortStr,
    pressure: tryParse(pres?['v']),
    waterLevel: tryParse(wlev?['v']),
    salinity: tryParse(sal?['s']),
    pressureTrend: pressureTrend,
  );
}

NwsForecast? _parseNws(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final hourly = raw['hourly'] as List?;
  if (hourly == null || hourly.isEmpty) return null;
  final cur = hourly[0] as Map<String, dynamic>;
  final periods = <NwsPeriod>[];
  for (final p in (raw['forecast'] as List? ?? [])) {
    periods.add(NwsPeriod(
      name: p['name'] as String? ?? '',
      shortForecast: p['shortForecast'] as String? ?? '',
      detail: p['detailedForecast'] as String? ?? '',
      temp: (p['temperature'] as num?)?.toInt() ?? 0,
    ));
  }
  return NwsForecast(
    condition: cur['shortForecast'] as String? ?? '',
    temp: (cur['temperature'] as num?)?.toInt() ?? 0,
    rainPct: (cur['probabilityOfPrecipitation']?['value'] as num?)?.toInt() ?? 0,
    windSpeed: cur['windSpeed'] as String? ?? '',
    windDir: cur['windDirection'] as String? ?? '',
    periods: periods,
  );
}

// ── Hourly interpolation from hi/lo (for subordinate stations) ────────────────

Map<int, double> _interpolateHourlyFromHilo(List<TidePrediction> hilo) {
  if (hilo.length < 2) return {};
  final sorted = [...hilo]..sort((a, b) => a.time.compareTo(b.time));
  // Convert to (fractional hour, height) pairs, adding synthetic boundary
  // points one full tidal period (~12.4h) before first and after last.
  final pts = <(double, double)>[];
  final period = 12.42; // avg tidal period in hours
  final first = sorted.first;
  final last = sorted.last;
  final firstH = first.time.hour + first.time.minute / 60.0;
  final lastH = last.time.hour + last.time.minute / 60.0;
  // Mirror boundary points so edges of the day are covered.
  pts.add((firstH - period, first.height));
  for (final p in sorted) {
    pts.add((p.time.hour + p.time.minute / 60.0, p.height));
  }
  pts.add((lastH + period, last.height));

  final out = <int, double>{};
  for (var hour = 0; hour < 24; hour++) {
    final h = hour.toDouble();
    // Find the two bracketing points.
    int? lo, hi;
    for (var i = 0; i < pts.length; i++) {
      if (pts[i].$1 <= h) lo = i;
      if (pts[i].$1 >= h && hi == null) hi = i;
    }
    if (lo == null || hi == null || lo == hi) {
      out[hour] = lo != null ? pts[lo].$2 : pts[hi!].$2;
    } else {
      final t1 = pts[lo].$1, t2 = pts[hi].$1;
      final h1 = pts[lo].$2, h2 = pts[hi].$2;
      final frac = (h - t1) / (t2 - t1);
      // Cosine interpolation mirrors the sinusoidal tide curve.
      out[hour] = h1 + (h2 - h1) * (1 - cos(pi * frac)) / 2;
    }
  }
  return out;
}

// ── NWS conditions supplement ─────────────────────────────────────────────────

Conditions _supplementFromNws(Conditions c, NwsForecast? nws) {
  if (nws == null) return c;
  // Only fill fields that NOAA obs couldn't provide.
  if (c.airTemp != null && c.windSpeed != null) return c;

  double? nwsWind;
  String? nwsWindDir;
  String? nwsBeaufort;
  if (c.windSpeed == null && nws.windSpeed.isNotEmpty) {
    // NWS gives "7 mph" or "7 to 12 mph" — take first number.
    final m = RegExp(r'(\d+)').firstMatch(nws.windSpeed);
    if (m != null) {
      nwsWind = double.tryParse(m.group(1)!);
      if (nwsWind != null) nwsBeaufort = beaufort(nwsWind);
    }
  }
  if (c.windDirStr == null && nws.windDir.isNotEmpty) {
    nwsWindDir = nws.windDir;
  }

  return Conditions(
    airTemp:      c.airTemp      ?? (nws.temp > 0 ? nws.temp.toDouble() : null),
    waterTemp:    c.waterTemp,
    windSpeed:    c.windSpeed    ?? nwsWind,
    windDir:      c.windDir,
    windGust:     c.windGust,
    windDirStr:   c.windDirStr   ?? nwsWindDir,
    beaufortStr:  c.beaufortStr  ?? nwsBeaufort,
    pressure:     c.pressure,
    waterLevel:   c.waterLevel,
    salinity:     c.salinity,
    pressureTrend: c.pressureTrend,
  );
}

// ── Master fetch ───────────────────────────────────────────────────────────────

Future<TideData> fetchAllData(Station station, {DateTime? targetDate}) async {
  final date = targetDate ?? DateTime.now();
  final dateOnly = DateTime(date.year, date.month, date.day);
  final dateStr = _dateFmt.format(dateOnly);
  final utcOff = _centralUtcOffset(dateOnly);
  final id = station.id;
  final lat = station.lat;
  final lon = station.lon;

  final results = await Future.wait([
    _fetchPredictions(id, dateStr, 'h'),       // 0
    _fetchPredictions(id, dateStr, 'hilo'),    // 1
    _fetchObs(id, 'air_temperature'),          // 2
    _fetchObs(id, 'wind'),                     // 3
    _fetchObs(id, 'air_pressure'),             // 4
    _fetchPressureTrend(id),                   // 5
    _fetchObs(id, 'water_temperature'),        // 6
    _fetchWaterLevel(id),                      // 7
    _fetchNws(lat, lon),                       // 8
    _fetchObs(id, 'salinity'),                 // 9
    fetchNdbcWaves(lat, lon),                  // 10
  ]);

  final hourlyList = results[0] as List<TidePrediction>;
  final hilo = results[1] as List<TidePrediction>;
  final pressureTrend = results[5] as int;
  final nwsRaw = results[8] as Map<String, dynamic>?;
  final waves = results[10] as WaveData?;

  // Build hourly map; fall back to cosine interpolation from hi/lo when the
  // station is a subordinate that only publishes hi/lo predictions.
  final hourly = <int, double>{};
  for (final p in hourlyList) {
    hourly[p.time.hour] = p.height;
  }
  if (hourly.isEmpty && hilo.isNotEmpty) {
    hourly.addAll(_interpolateHourlyFromHilo(hilo));
  }

  final obsRaw = <String, dynamic?>{
    'air_temperature': results[2],
    'wind': results[3],
    'air_pressure': results[4],
    'water_temperature': results[6],
    'water_level': results[7],
    'salinity': results[9],
  };
  var conditions = _parseConditions(obsRaw, pressureTrend);
  final nws = _parseNws(nwsRaw);

  // Fill missing NOAA obs fields from NWS for stations without met sensors.
  conditions = _supplementFromNws(conditions, nws);

  final sun = sunTimes(dateOnly, lat, lon, utcOff);
  final moon = moonPhase(dateOnly);
  final solunar = solunarTimes(dateOnly, lon, utcOff);
  final isToday = dateOnly == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final fishing = isToday ? fishingRating(hilo, conditions.windSpeed, solunar)
      : const FishingInfo(stars: 0, label: 'N/A');

  return TideData(
    stationId: id,
    lat: lat,
    lon: lon,
    targetDate: dateOnly,
    isToday: isToday,
    hourly: hourly,
    hilo: hilo,
    conditions: conditions,
    nws: nws,
    sun: sun,
    moon: moon,
    solunar: solunar,
    fishing: fishing,
    waves: waves,
  );
}

Future<List<TidePrediction>> fetchWeekHilo(
    String stationId, DateTime start, DateTime end) async {
  final url = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter'
      '?begin_date=${_dateFmt.format(start)}'
      '&end_date=${_dateFmt.format(end)}'
      '&station=$stationId'
      '&product=predictions&datum=MLLW&time_zone=lst_ldt'
      '&interval=hilo&units=english&format=json&application=tides_flutter';
  final data = await apiGet(url);
  return _parsePredictions((data?['predictions'] as List?) ?? []);
}
