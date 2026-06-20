import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
export '../models/tide_data.dart' show WaveData;

final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)));
final _dateFmt = DateFormat('yyyyMMdd');

// ── Two-tier TTL cache (in-memory + disk) ──────────────────────────────────────
// Today's entry blends in live observations, so it expires quickly; every other
// day is pure (static) tide predictions + that day's forecast and stays valid
// for the rest of the day. Tide predictions are astronomical and never change,
// so each computed day is also mirrored to SharedPreferences and rehydrated on
// the next cold start (see [hydrateCacheFromDisk]) — that way reopening the app
// after Android has evicted the process doesn't refetch every day you scrub to.
const _cacheTtl = Duration(minutes: 30);          // today (live conditions)
const _staticTtl = Duration(hours: 12);           // other days (predictions)
final _tideCache = <String, ({TideData data, DateTime fetchedAt})>{};
final _weekCache = <String, ({List<TidePrediction> data, DateTime fetchedAt})>{};

const _tideDiskPrefix = 'tcache_';
const _weekDiskPrefix = 'wcache_';

String _tideCacheKey(String id, DateTime date) => '$id-${_dateFmt.format(date)}';
String _weekCacheKey(String id, DateTime s, DateTime e) =>
    '$id-week-${_dateFmt.format(s)}-${_dateFmt.format(e)}';

DateTime _todayOnly() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Duration _ttlFor(DateTime dateOnly) =>
    dateOnly == _todayOnly() ? _cacheTtl : _staticTtl;

/// Whether a cached [TideData] may still be served. Beyond the TTL check this
/// rejects an entry whose today-ness has flipped (the app sat open across
/// midnight, or a stale "today" was rehydrated from disk) — those carry live
/// conditions that would otherwise be shown for the wrong day.
bool _tideFresh(TideData d, DateTime fetchedAt) {
  if (d.isToday != (d.targetDate == _todayOnly())) return false;
  return DateTime.now().difference(fetchedAt) < _ttlFor(d.targetDate);
}

/// Warms the cache for [stations] across a 10-day window. Prefetches 2 days
/// back + today + 7 days ahead so forward/back navigation is instant. Skips
/// days that are already cached and fresh (in memory or rehydrated from disk).
void schedulePrefetch(List<Station> stations) {
  final today = _todayOnly();
  // Offsets: -2, -1, 0 (today), +1 … +7
  for (var offset = -2; offset <= 7; offset++) {
    final date = today.add(Duration(days: offset));
    for (final station in stations) {
      final cached = _tideCache[_tideCacheKey(station.id, date)];
      if (cached != null && _tideFresh(cached.data, cached.fetchedAt)) continue;
      fetchAllData(station, targetDate: date).ignore();
    }
  }
}

/// Loads previously-persisted station-days back into the in-memory cache on
/// startup so a cold launch can serve them without any network call. Drops
/// entries that are too old, for days we no longer navigate to, or whose
/// today-ness has since flipped. Best-effort: any failure just leaves the
/// cache cold. Call once, before the first screen reads tide data.
Future<void> hydrateCacheFromDisk() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = _todayOnly();
    final cutoff = today.subtract(const Duration(days: 2)); // matches prefetch window
    for (final k in sp.getKeys().toList()) {
      try {
        if (k.startsWith(_tideDiskPrefix)) {
          final raw = sp.getString(k);
          if (raw == null) continue;
          final j = jsonDecode(raw) as Map<String, dynamic>;
          final fetchedAt = DateTime.fromMillisecondsSinceEpoch(j['f'] as int);
          final data = _tideFromJson(j['d'] as Map<String, dynamic>);
          final stale = data.targetDate.isBefore(cutoff) ||
              now.difference(fetchedAt) > const Duration(days: 7) ||
              data.isToday != (data.targetDate == today);
          if (stale) {
            await sp.remove(k);
            continue;
          }
          _tideCache[k.substring(_tideDiskPrefix.length)] =
              (data: data, fetchedAt: fetchedAt);
        } else if (k.startsWith(_weekDiskPrefix)) {
          final raw = sp.getString(k);
          if (raw == null) continue;
          final j = jsonDecode(raw) as Map<String, dynamic>;
          final fetchedAt = DateTime.fromMillisecondsSinceEpoch(j['f'] as int);
          if (now.difference(fetchedAt) > const Duration(days: 7)) {
            await sp.remove(k);
            continue;
          }
          final list = (j['d'] as List)
              .map((e) => _predFromJson(e as Map<String, dynamic>))
              .toList();
          _weekCache[k.substring(_weekDiskPrefix.length)] =
              (data: list, fetchedAt: fetchedAt);
        }
      } catch (_) {
        await sp.remove(k); // corrupt/unreadable entry
      }
    }
  } catch (_) {/* best-effort — cache stays cold */}
}

// Mirror a freshly-computed entry to disk (fire-and-forget). Wraps the payload
// with its fetch timestamp so TTLs survive a restart.
void _persistTide(String key, TideData data, DateTime fetchedAt) {
  () async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          '$_tideDiskPrefix$key',
          jsonEncode({'f': fetchedAt.millisecondsSinceEpoch, 'd': _tideToJson(data)}));
    } catch (_) {/* best-effort */}
  }();
}

void _persistWeek(String key, List<TidePrediction> data, DateTime fetchedAt) {
  () async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          '$_weekDiskPrefix$key',
          jsonEncode({
            'f': fetchedAt.millisecondsSinceEpoch,
            'd': data.map(_predToJson).toList(),
          }));
    } catch (_) {/* best-effort */}
  }();
}

// ── TideData ⇄ JSON (for the disk cache) ───────────────────────────────────────
// Compact keys keep the persisted blobs small. Doubles round-trip through num.

double? _d(dynamic v) => (v as num?)?.toDouble();

Map<String, dynamic> _predToJson(TidePrediction p) => {
      't': p.time.millisecondsSinceEpoch,
      'h': p.height,
      if (p.type != null) 'y': p.type,
    };
TidePrediction _predFromJson(Map<String, dynamic> j) => TidePrediction(
      time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      height: (j['h'] as num).toDouble(),
      type: j['y'] as String?,
    );

Map<String, dynamic> _condToJson(Conditions c) => {
      'at': c.airTemp, 'wt': c.waterTemp, 'ws': c.windSpeed, 'wd': c.windDir,
      'wg': c.windGust, 'pr': c.pressure, 'wl': c.waterLevel, 'sa': c.salinity,
      'wds': c.windDirStr, 'bs': c.beaufortStr, 'pt': c.pressureTrend,
      'wti': c.windTide,
    };
Conditions _condFromJson(Map<String, dynamic> j) => Conditions(
      airTemp: _d(j['at']), waterTemp: _d(j['wt']), windSpeed: _d(j['ws']),
      windDir: _d(j['wd']), windGust: _d(j['wg']), pressure: _d(j['pr']),
      waterLevel: _d(j['wl']), salinity: _d(j['sa']),
      windDirStr: j['wds'] as String?, beaufortStr: j['bs'] as String?,
      pressureTrend: (j['pt'] as num?)?.toInt() ?? 0, windTide: _d(j['wti']),
    );

Map<String, dynamic>? _nwsToJson(NwsForecast? n) => n == null
    ? null
    : {
        'c': n.condition, 't': n.temp, 'r': n.rainPct, 'ws': n.windSpeed,
        'wd': n.windDir,
        'p': n.periods
            .map((p) => {
                  'n': p.name, 's': p.shortForecast, 'd': p.detail, 't': p.temp,
                })
            .toList(),
      };
NwsForecast? _nwsFromJson(Map<String, dynamic>? j) => j == null
    ? null
    : NwsForecast(
        condition: j['c'] as String, temp: (j['t'] as num).toInt(),
        rainPct: (j['r'] as num).toInt(), windSpeed: j['ws'] as String,
        windDir: j['wd'] as String,
        periods: ((j['p'] as List?) ?? [])
            .map((e) => e as Map<String, dynamic>)
            .map((m) => NwsPeriod(
                  name: m['n'] as String, shortForecast: m['s'] as String,
                  detail: m['d'] as String, temp: (m['t'] as num).toInt(),
                ))
            .toList(),
      );

Map<String, dynamic>? _waveToJson(WaveData? w) => w == null
    ? null
    : {
        'wh': w.waveHeight, 'dp': w.domPeriod, 'wd': w.waveDir,
        'sh': w.swellHeight, 'sp': w.swellPeriod, 'sd': w.swellDir,
        'wwh': w.windWaveHeight, 'wwp': w.windWavePeriod, 'src': w.source,
      };
WaveData? _waveFromJson(Map<String, dynamic>? j) => j == null
    ? null
    : WaveData(
        waveHeight: (j['wh'] as num).toDouble(),
        domPeriod: (j['dp'] as num).toDouble(),
        waveDir: j['wd'] as String?, swellHeight: _d(j['sh']),
        swellPeriod: _d(j['sp']), swellDir: j['sd'] as String?,
        windWaveHeight: _d(j['wwh']), windWavePeriod: _d(j['wwp']),
        source: j['src'] as String,
      );

Map<String, dynamic> _tideToJson(TideData d) => {
      'id': d.stationId, 'lat': d.lat, 'lon': d.lon,
      'date': d.targetDate.millisecondsSinceEpoch, 'today': d.isToday,
      'hr': {for (final e in d.hourly.entries) '${e.key}': e.value},
      'hl': d.hilo.map(_predToJson).toList(),
      'cond': _condToJson(d.conditions),
      'nws': _nwsToJson(d.nws),
      'sun': {'sr': d.sun.sunrise, 'ss': d.sun.sunset, 'n': d.sun.noon, 'g': d.sun.golden},
      'moon': {'p': d.moon.phase, 'pct': d.moon.pct},
      'sol': {'M1': d.solunar.major1, 'M2': d.solunar.major2,
              'm1': d.solunar.minor1, 'm2': d.solunar.minor2},
      'fish': {
        's': d.fishing.stars, 'l': d.fishing.label, 'mv': d.fishing.movement,
        'w': d.fishing.windows
            .map((w) => {'s': w.startH, 'e': w.endH, 'r': w.reason})
            .toList(),
      },
      'wave': _waveToJson(d.waves),
    };

TideData _tideFromJson(Map<String, dynamic> j) {
  final sun = j['sun'] as Map<String, dynamic>;
  final moon = j['moon'] as Map<String, dynamic>;
  final sol = j['sol'] as Map<String, dynamic>;
  final fish = j['fish'] as Map<String, dynamic>;
  return TideData(
    stationId: j['id'] as String,
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    targetDate: DateTime.fromMillisecondsSinceEpoch(j['date'] as int),
    isToday: j['today'] as bool,
    hourly: (j['hr'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())),
    hilo: (j['hl'] as List)
        .map((e) => _predFromJson(e as Map<String, dynamic>))
        .toList(),
    conditions: _condFromJson(j['cond'] as Map<String, dynamic>),
    nws: _nwsFromJson(j['nws'] as Map<String, dynamic>?),
    sun: SunInfo(
        sunrise: sun['sr'] as String, sunset: sun['ss'] as String,
        noon: sun['n'] as String, golden: sun['g'] as String),
    moon: MoonInfo(phase: moon['p'] as String, pct: (moon['pct'] as num).toInt()),
    solunar: SolunarInfo(
        major1: (sol['M1'] as num).toDouble(), major2: (sol['M2'] as num).toDouble(),
        minor1: (sol['m1'] as num).toDouble(), minor2: (sol['m2'] as num).toDouble()),
    fishing: FishingInfo(
      stars: (fish['s'] as num).toInt(),
      label: fish['l'] as String,
      movement: fish['mv'] as String?,
      windows: ((fish['w'] as List?) ?? [])
          .map((e) => e as Map<String, dynamic>)
          .map((m) => BiteWindow(
                startH: (m['s'] as num).toDouble(),
                endH: (m['e'] as num).toDouble(),
                reason: m['r'] as String,
              ))
          .toList(),
    ),
    waves: _waveFromJson(j['wave'] as Map<String, dynamic>?),
  );
}

// ISO date (yyyy-MM-dd) for Open-Meteo start_date/end_date params.
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
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
  return r * 2 * asin(sqrt(max(0, min(1, a))));
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
  // Round to whole minutes FIRST, then split into h/m. Rounding the minutes on
  // their own can carry to 60 (e.g. 6.999h → "6:60"); collapsing to a single
  // minute count and wrapping a full day keeps the carry correct (→ "7:00",
  // and 23:59.7 → "12:00 AM").
  final mins = ((decimalHours % 24) * 60).round() % (24 * 60);
  final hh = mins ~/ 60;
  final mm = mins % 60;
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

/// A station's time zone, read once from NOAA station metadata and cached for
/// the process. [corr] is the STANDARD-time GMT offset (no DST); [abbr] is
/// NOAA's zone code (CST, EST, HAST, …), used to tell whether the station
/// shifts for daylight saving.
class _StationTz {
  final double corr;
  final String abbr;
  const _StationTz(this.corr, this.abbr);
}

final Map<String, _StationTz> _tzCache = {};

/// Zones (by NOAA abbreviation) that do NOT observe daylight saving. Coastal US
/// tide stations all shift for DST except Hawaii and the non-DST island
/// territories (Atlantic/Samoa/Chamorro); Arizona has no coastal stations.
const _noDstZones = {'HST', 'HAST', 'AST', 'SST', 'ChST', 'GST'};

/// Fetch (and cache) the station's time zone from NOAA's metadata API. Falls
/// back to a longitude estimate of the standard offset if the call fails, so a
/// network hiccup lands in the right zone rather than forcing Central time.
Future<_StationTz> _stationTz(Station station) async {
  final cached = _tzCache[station.id];
  if (cached != null) return cached;
  try {
    final url =
        'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations/'
        '${station.id}.json';
    final data = await apiGet(url);
    final s = (data?['stations'] as List?)?.first as Map<String, dynamic>?;
    final corr = (s?['timezonecorr'] as num?)?.toDouble();
    if (corr != null) {
      final tz = _StationTz(corr, (s?['timezone'] as String?) ?? '');
      _tzCache[station.id] = tz;
      return tz;
    }
  } catch (_) {}
  return _StationTz((station.lon / 15).roundToDouble(), '');
}

/// The local offset NOAA uses for `lst_ldt`: the station's standard offset plus
/// an hour during the US DST window for zones that observe it.
double _localUtcOffset(_StationTz tz, DateTime d) {
  final observesDst = !_noDstZones.contains(tz.abbr);
  return tz.corr + (observesDst && _isUsDst(d) ? 1.0 : 0.0);
}

bool _isUsDst(DateTime d) {
  final y = d.year;
  final dstStart = List.generate(7, (i) => DateTime(y, 3, 8 + i))
      .firstWhere((dt) => dt.weekday == DateTime.sunday);
  final dstEnd = List.generate(7, (i) => DateTime(y, 11, 1 + i))
      .firstWhere((dt) => dt.weekday == DateTime.sunday);
  final dateOnly = DateTime(d.year, d.month, d.day);
  return dateOnly.isAfter(dstStart.subtract(const Duration(days: 1))) &&
      dateOnly.isBefore(dstEnd);
}

// Day-level fishing rating for a future date (no real-time wind or clock).
// Scores how well the major solunar periods align with the day's tide changes —
// the core of classic lunar fishing calendars.
FishingInfo fishingRatingDay(List<TidePrediction> hilo, SolunarInfo sol) {
  if (hilo.isEmpty) return const FishingInfo(stars: 1, label: 'Poor');

  // Find closest gap between any major solunar period and any tide change.
  var minDist = 24.0;
  var bestMajorH = sol.major1;
  for (final maj in [sol.major1, sol.major2]) {
    for (final p in hilo) {
      final tidH = p.time.hour + p.time.minute / 60;
      final d = (tidH - maj).abs();
      final dist = d > 12 ? 24 - d : d;
      if (dist < minDist) {
        minDist = dist;
        bestMajorH = maj;
      }
    }
  }

  // Base score: tighter alignment = higher potential.
  final score = minDist < 1.0 ? 4
              : minDist < 2.0 ? 3
              : minDist < 3.0 ? 2
              : 1;

  // Bonus: major during prime fishing hours (dawn 5–9 AM or dusk 4–8 PM).
  final isPrime = (bestMajorH >= 5 && bestMajorH < 9) ||
                  (bestMajorH >= 16 && bestMajorH < 20);
  final clamped = (isPrime && score >= 3 ? score + 1 : score).clamp(1, 5);
  final label = {5: 'Excellent', 4: 'Very Good', 3: 'Good', 2: 'Fair'}[clamped] ?? 'Poor';
  return FishingInfo(stars: clamped, label: label);
}

FishingInfo fishingRating(
    List<TidePrediction> hilo, double? windMph, SolunarInfo sol,
    {int pressureTrend = 0, Map<int, double>? hourly}) {
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

  // Moving water: fish feed on current, not slack. Score the tide's rate of
  // change now relative to the day's strongest movement (station-agnostic).
  if (hourly != null && hourly.length > 2) {
    final maxSlope = _maxAbsSlope(hourly);
    if (maxSlope > 0.01) {
      final ratio = tideSlope(hourly, nowH).abs() / maxSlope;
      if (ratio > 0.66) {
        score += 2;
      } else if (ratio > 0.33) {
        score += 1;
      }
    }
  }

  // Falling barometer = pre-front feeding bump.
  if (pressureTrend < 0) score += 1;

  final clamped = min(score, 5);
  final label = {5: 'Excellent', 4: 'Very Good', 3: 'Good', 2: 'Fair'}[clamped] ?? 'Poor';
  return FishingInfo(stars: clamped, label: label);
}

// Observed water level minus the predicted tide height at `now`, interpolated
// linearly between the two surrounding hourly predictions. Returns null when
// either input is missing. Positive = water stacked above prediction.
double? windTideResidual(
    double? observed, Map<int, double> hourly, DateTime now) {
  if (observed == null || hourly.isEmpty) return null;
  final h = now.hour;
  final frac = now.minute / 60.0;
  final lo = hourly[h];
  final hi = hourly[(h + 1) % 24] ?? lo;
  if (lo == null) return null;
  final predicted = lo + (hi! - lo) * frac;
  return observed - predicted;
}

// Central-difference slope of the predicted tide curve at `atH` (ft per hour),
// falling back to one-sided differences at the ends of the day.
double tideSlope(Map<int, double> hourly, double atH) {
  final h = atH.round().clamp(0, 23);
  final b = hourly[h];
  if (b == null) return 0;
  final a = hourly[h - 1];
  final c = hourly[h + 1];
  if (a != null && c != null) return (c - a) / 2.0;
  if (c != null) return c - b;
  if (a != null) return b - a;
  return 0;
}

double _maxAbsSlope(Map<int, double> hourly) {
  var m = 0.0;
  for (var h = 0; h < 24; h++) {
    final s = tideSlope(hourly, h.toDouble()).abs();
    if (s > m) m = s;
  }
  return m;
}

String _hourLabel(int h) {
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh ${h < 12 || h == 24 ? 'AM' : 'PM'}';
}

// Today's best 2–3 bite windows plus a one-line movement summary. Windows are
// scored per-hour from tide movement + solunar proximity + dawn/dusk, then the
// top non-overlapping peaks are returned. Pure function over already-fetched
// data — no network.
({String? movement, List<BiteWindow> windows}) computeBiteWindows(
    Map<int, double> hourly, SolunarInfo sol, {DateTime? now}) {
  if (hourly.length < 4) return (movement: null, windows: const []);
  final maxSlope = _maxAbsSlope(hourly);

  double solunarBoost(double h) {
    var best = 0.0;
    for (final m in [sol.major1, sol.major2]) {
      final d = (h - m).abs();
      final dist = d > 12 ? 24 - d : d;
      if (dist < 1) {
        best = max(best, 2.0);
      } else if (dist < 2) {
        best = max(best, 1.0);
      }
    }
    for (final m in [sol.minor1, sol.minor2]) {
      final d = (h - m).abs();
      final dist = d > 12 ? 24 - d : d;
      if (dist < 1) best = max(best, 0.5);
    }
    return best;
  }

  final scores = <int, double>{};
  for (var h = 0; h < 24; h++) {
    final move = maxSlope > 0.01
        ? (tideSlope(hourly, h.toDouble()).abs() / maxSlope) * 2.0
        : 0.0;
    final sun = (h >= 5 && h < 9) || (h >= 16 && h < 20) ? 0.75 : 0.0;
    scores[h] = move + solunarBoost(h.toDouble()) + sun;
  }

  // Greedily pick the top-scoring hours, keeping windows ≥3h apart.
  final ranked = scores.keys.toList()
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  final centers = <int>[];
  for (final h in ranked) {
    if (scores[h]! < 1.5) break;
    if (centers.every((c) => (c - h).abs() >= 3)) centers.add(h);
    if (centers.length == 3) break;
  }
  centers.sort();

  final windows = <BiteWindow>[];
  for (final c in centers) {
    final rising = tideSlope(hourly, c.toDouble()) >= 0;
    final tide = maxSlope > 0.01 &&
            tideSlope(hourly, c.toDouble()).abs() / maxSlope > 0.33
        ? (rising ? 'Incoming' : 'Outgoing')
        : null;
    final sol2 = solunarBoost(c.toDouble()) >= 1.0 ? 'Major' : null;
    final reason = [tide, sol2].whereType<String>().join(' + ');
    windows.add(BiteWindow(
      startH: (c - 1).toDouble().clamp(0, 23),
      endH: (c + 1).toDouble().clamp(0, 23),
      reason: reason.isEmpty ? 'Prime' : reason,
    ));
  }

  // Movement summary anchored on the current hour.
  String? movement;
  if (maxSlope > 0.01) {
    final n = (now ?? DateTime.now());
    final nowH = n.hour + n.minute / 60;
    final s = tideSlope(hourly, nowH);
    final dir = s.abs() / maxSlope < 0.2
        ? 'Slack'
        : (s >= 0 ? 'Incoming' : 'Outgoing');
    var peak = 0;
    var peakV = 0.0;
    for (var h = 0; h < 24; h++) {
      final v = tideSlope(hourly, h.toDouble()).abs();
      if (v > peakV) {
        peakV = v;
        peak = h;
      }
    }
    movement = dir == 'Slack'
        ? 'Slack water — strongest ${_hourLabel(peak)}–${_hourLabel((peak + 2) % 24)}'
        : '$dir — strongest ${_hourLabel(peak)}–${_hourLabel((peak + 2) % 24)}';
  }

  return (movement: movement, windows: windows);
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

// ── Open-Meteo Marine wave data ───────────────────────────────────────────────

// Marine wave data. For today we read live "current" values; for a future day
// we read that day's hourly forecast and take the midday (noon) sample, so the
// Waves card follows the day/week navigation like a real marine forecast.
Future<WaveData?> fetchOpenMeteoWaves(double lat, double lon,
    {DateTime? day}) async {
  final now = DateTime.now();
  final isToday = day == null ||
      (day.year == now.year && day.month == now.month && day.day == now.day);
  const waveVars = 'wave_height,wave_direction,wave_period,'
      'wind_wave_height,wind_wave_direction,wind_wave_period,'
      'swell_wave_height,swell_wave_direction,swell_wave_period';
  final base = 'https://marine-api.open-meteo.com/v1/marine'
      '?latitude=$lat&longitude=$lon&length_unit=imperial&timezone=auto';
  final url = isToday
      ? '$base&current=$waveVars'
      : '$base&hourly=$waveVars&start_date=${_ymd(day)}&end_date=${_ymd(day)}';
  final data = await apiGet(url);

  Map<String, dynamic>? c;
  if (isToday) {
    c = data?['current'] as Map<String, dynamic>?;
  } else {
    final h = data?['hourly'] as Map<String, dynamic>?;
    if (h != null) {
      // Noon sample (index 12) of the single requested day.
      double? at(String k) {
        final l = h[k] as List?;
        return (l != null && l.length > 12) ? (l[12] as num?)?.toDouble() : null;
      }
      c = {for (final k in waveVars.split(',')) k: at(k)};
    }
  }
  if (c == null) return null;
  final wh = (c['wave_height'] as num?)?.toDouble();
  if (wh == null || wh == 0) return null;
  final dir = (c['wave_direction'] as num?)?.toDouble();
  final period = (c['wave_period'] as num?)?.toDouble() ?? 0;
  final swh = (c['swell_wave_height'] as num?)?.toDouble();
  final swp = (c['swell_wave_period'] as num?)?.toDouble();
  final swd = (c['swell_wave_direction'] as num?)?.toDouble();
  final wwh = (c['wind_wave_height'] as num?)?.toDouble();
  final wwp = (c['wind_wave_period'] as num?)?.toDouble();
  return WaveData(
    waveHeight: wh,
    domPeriod: period,
    waveDir: dir != null ? windDirArrow(dir) : null,
    swellHeight: (swh != null && swh > 0) ? swh : null,
    swellPeriod: swp,
    swellDir: swd != null ? windDirArrow(swd) : null,
    windWaveHeight: (wwh != null && wwh > 0) ? wwh : null,
    windWavePeriod: wwp,
    source: isToday ? 'Open-Meteo' : 'Open-Meteo forecast',
  );
}

// Forecast conditions for a future day (Open-Meteo land + marine), sampled at
// noon. Used in place of NOAA live observations when the user navigates to a
// day other than today, so the Conditions card reflects that day's forecast.
Future<Conditions?> fetchForecastConditions(
    double lat, double lon, DateTime day) async {
  final d = _ymd(day);
  final landUrl = 'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,'
      'wind_gusts_10m,pressure_msl'
      '&start_date=$d&end_date=$d'
      '&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto';
  final seaUrl = 'https://marine-api.open-meteo.com/v1/marine'
      '?latitude=$lat&longitude=$lon&hourly=sea_surface_temperature'
      '&start_date=$d&end_date=$d&timezone=auto';

  final res = await Future.wait([apiGet(landUrl), apiGet(seaUrl)]);
  final h = res[0]?['hourly'] as Map<String, dynamic>?;
  if (h == null) return null;

  double? at(Map<String, dynamic>? hh, String k) {
    final l = hh?[k] as List?;
    return (l != null && l.length > 12) ? (l[12] as num?)?.toDouble() : null;
  }

  final windSpeed = at(h, 'wind_speed_10m');
  final windDir = at(h, 'wind_direction_10m');
  final sstC = at(res[1]?['hourly'] as Map<String, dynamic>?,
      'sea_surface_temperature');

  return Conditions(
    airTemp: at(h, 'temperature_2m'),
    waterTemp: sstC != null ? sstC * 9 / 5 + 32 : null, // marine SST is °C
    windSpeed: windSpeed,
    windDir: windDir,
    windGust: at(h, 'wind_gusts_10m'),
    windDirStr: windDir != null ? windDirArrow(windDir) : null,
    beaufortStr: windSpeed != null ? beaufort(windSpeed) : null,
    pressure: at(h, 'pressure_msl'),
    waterLevel: null, // set by caller from the day's predicted tide
    salinity: null,
    pressureTrend: 0,
  );
}

// ── Sea-surface temperature anomaly (upwelling signal) ───────────────────────
//
// NOAA CoastWatch ERDDAP, JPL MUR daily SST anomaly vs. the long-term normal.
// A strongly negative anomaly near the coast usually means upwelling (or a
// cold-front cooldown) — either way, colder-than-normal water moving in.
// Only the pfeg host is used: the coastwatch.noaa.gov mirror has been
// unreliable (503s) while pfeg stayed up.
const _erddap = 'https://coastwatch.pfeg.noaa.gov/erddap/griddap';

/// Mean SST anomaly (°C) in a ±0.15° box around (lat,lon) from the MUR daily
/// anomaly grid. Negative = colder than normal = possible upwelling. Null when
/// every cell is land-masked or ERDDAP is unreachable. The grid updates daily,
/// so results are cached per rounded point per UTC day; a NaN sentinel marks
/// "fetched, no data" so a down server isn't re-queried on every refresh.
Future<double?> fetchSstAnomaly(double lat, double lon) async {
  final day = DateTime.now().toUtc();
  final key = 'sstAnom_${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}_'
      '${_dateFmt.format(day)}';
  final sp = await SharedPreferences.getInstance();
  final cached = sp.getDouble(key);
  if (cached != null) return cached.isNaN ? null : cached;

  final url = '$_erddap/jplMURSST41anom1day.json'
      '?sstAnom%5B(last)%5D'
      '%5B(${lat - 0.15}):(${lat + 0.15})%5D'
      '%5B(${lon - 0.15}):(${lon + 0.15})%5D';
  final data = await apiGet(url);
  final rows = data?['table']?['rows'] as List?;
  if (rows == null) return null; // transient failure — don't cache

  final vals = [
    for (final r in rows)
      if ((r as List).last != null) (r.last as num).toDouble()
  ];
  if (vals.isEmpty) {
    await sp.setDouble(key, double.nan);
    return null;
  }
  final mean = vals.reduce((a, b) => a + b) / vals.length;
  await sp.setDouble(key, mean);
  return mean;
}

// ── Station capability map ────────────────────────────────────────────────────
//
// NOAA mdapi valid type= values:
//   type=waterlevels → 301 stations with live water-level sensors → wl
//   type=met         → 318 stations with met sensors              → wind, at, pres
//   type=physocean   → 240 stations with water temp ONLY          → wt
//                      (physocean ≠ salinity — verified by probing all 301
//                       waterlevels stations; only 21 have salinity sensors)
//
// NOAA has no type=salinity endpoint. The 21 salinity stations were found by
// probing every waterlevels station for product=salinity live data.

const _salinityStations = {
  '8419870', '8447386', '8452660', '8518962', '8518979',
  '8557380', '8573927', '8574680', '8632200', '8635750',
  '8637689', '8638610', '8639348', '8720218', '8720219',
  '8726674', '8737048', '8770613', '8771013', '8775222',
  '9454050',
};

Future<Map<String, Set<String>>> fetchCapabilityMap() async {
  const base =
      'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=';

  final results = await Future.wait([
    apiGet('${base}waterlevels'),
    apiGet('${base}met'),
    apiGet('${base}physocean'),
  ]);

  Set<String> ids(dynamic data) =>
      (data?['stations'] as List? ?? [])
          .map<String>((s) => s['id'] as String)
          .toSet();

  final wlIds   = ids(results[0]);
  final metIds  = ids(results[1]);
  final physIds = ids(results[2]);

  final map = <String, Set<String>>{};
  void add(String id, String cap) =>
      map.putIfAbsent(id, () => {}).add(cap);

  for (final id in wlIds)              { add(id, 'wl'); }
  for (final id in metIds)             { add(id, 'wind'); add(id, 'at'); add(id, 'pres'); }
  for (final id in physIds)            { add(id, 'wt'); }
  for (final id in _salinityStations)  { add(id, 'sal'); }

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

Conditions _parseConditions(Map<String, dynamic> obs, int pressureTrend) {
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
  const period = 12.42; // avg tidal period in hours
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
  final cacheKey = _tideCacheKey(station.id, dateOnly);
  final cached = _tideCache[cacheKey];
  if (cached != null && _tideFresh(cached.data, cached.fetchedAt)) {
    return cached.data;
  }
  final dateStr = _dateFmt.format(dateOnly);
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
    fetchOpenMeteoWaves(lat, lon, day: dateOnly), // 10
    _stationTz(station),                       // 11
  ]);

  final hourlyList = results[0] as List<TidePrediction>;
  final hilo = results[1] as List<TidePrediction>;
  final pressureTrend = results[5] as int;
  final nwsRaw = results[8] as Map<String, dynamic>?;
  final waves = results[10] as WaveData?;
  // Sun/solunar are computed locally, so they need the station's OWN local
  // offset (NOAA serves tide times in lst_ldt). Using a fixed Central offset
  // put sunrise/sunset hours off by the timezone difference everywhere outside
  // the Gulf (e.g. Honolulu was ~5 h wrong).
  final utcOff = _localUtcOffset(results[11] as _StationTz, dateOnly);

  // Build hourly map; fall back to cosine interpolation from hi/lo when the
  // station is a subordinate that only publishes hi/lo predictions.
  final hourly = <int, double>{};
  for (final p in hourlyList) {
    hourly[p.time.hour] = p.height;
  }
  if (hourly.isEmpty && hilo.isNotEmpty) {
    hourly.addAll(_interpolateHourlyFromHilo(hilo));
  }

  final obsRaw = <String, dynamic>{
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

  // NOAA only serves live (current) observations, so for any day other than
  // today the Conditions card would wrongly keep showing "now". Swap in the
  // day's Open-Meteo forecast (noon sample) so it follows the day/week arrows.
  // Water level uses the day's own predicted tide height at noon.
  if (!isToday) {
    final fc = await fetchForecastConditions(lat, lon, dateOnly);
    if (fc != null) {
      conditions = Conditions(
        airTemp: fc.airTemp,
        waterTemp: fc.waterTemp,
        windSpeed: fc.windSpeed,
        windDir: fc.windDir,
        windGust: fc.windGust,
        windDirStr: fc.windDirStr,
        beaufortStr: fc.beaufortStr,
        pressure: fc.pressure,
        waterLevel: hourly[12],
        salinity: null,
        pressureTrend: 0,
      );
    }
  }

  // Wind tide: observed water level vs. the predicted curve at this moment.
  // Only meaningful today (live observation) and when both values exist.
  if (isToday) {
    final wt = windTideResidual(conditions.waterLevel, hourly, DateTime.now());
    if (wt != null) conditions = conditions.copyWith(windTide: wt);
  }

  var fishing = isToday
      ? fishingRating(hilo, conditions.windSpeed, solunar,
          pressureTrend: conditions.pressureTrend, hourly: hourly)
      : fishingRatingDay(hilo, solunar);
  if (isToday) {
    final bite = computeBiteWindows(hourly, solunar);
    fishing = FishingInfo(
      stars: fishing.stars,
      label: fishing.label,
      windows: bite.windows,
      movement: bite.movement,
    );
  }

  final result = TideData(
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
  final fetchedAt = DateTime.now();
  _tideCache[cacheKey] = (data: result, fetchedAt: fetchedAt);
  _persistTide(cacheKey, result, fetchedAt);
  if (isToday) _writeCarSummary(result);
  return result;
}

/// Caches a compact per-station summary (fishing/sun/moon) to SharedPreferences
/// so the Android Auto car module can show the phone-computed values without
/// re-deriving the astronomy/solunar math in Kotlin. Fire-and-forget.
void _writeCarSummary(TideData d) {
  () async {
    try {
      // Format bite windows like the detail screen ("2–4 PM" / "11 AM–1 PM").
      String num(int h) => '${h % 12 == 0 ? 12 : h % 12}';
      String ap(int h) => h < 12 ? 'AM' : 'PM';
      String win(BiteWindow w) {
        final s = w.startH.round() % 24;
        final e = w.endH.round() % 24;
        return ap(s) == ap(e)
            ? '${num(s)}–${num(e)} ${ap(e)}'
            : '${num(s)} ${ap(s)}–${num(e)} ${ap(e)}';
      }

      final best = d.fishing.windows.take(3).map(win).join(', ');
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'stars': d.fishing.stars,
        'label': d.fishing.label,
        'best': best,
        'movement': d.fishing.movement ?? '',
        'sunrise': d.sun.sunrise,
        'sunset': d.sun.sunset,
        'moonPhase': d.moon.phase,
        'moonPct': d.moon.pct,
      });
      await prefs.setString('car_${d.stationId}', json);
    } catch (_) {/* best-effort */}
  }();
}

Future<List<TidePrediction>> fetchWeekHilo(
    String stationId, DateTime start, DateTime end) async {
  final key = _weekCacheKey(stationId, start, end);
  final cached = _weekCache[key];
  if (cached != null &&
      DateTime.now().difference(cached.fetchedAt) < _staticTtl) {
    return cached.data;
  }
  final url = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter'
      '?begin_date=${_dateFmt.format(start)}'
      '&end_date=${_dateFmt.format(end)}'
      '&station=$stationId'
      '&product=predictions&datum=MLLW&time_zone=lst_ldt'
      '&interval=hilo&units=english&format=json&application=tides_flutter';
  final data = await apiGet(url);
  final result = _parsePredictions((data?['predictions'] as List?) ?? []);
  final fetchedAt = DateTime.now();
  _weekCache[key] = (data: result, fetchedAt: fetchedAt);
  _persistWeek(key, result, fetchedAt);
  return result;
}
