import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/units_provider.dart';
import '../theme.dart';
import '../widgets/map_recenter_button.dart';

// ── Color ramps (opacity baked in) ───────────────────────────────────────────
// Piecewise-linear ramps: values lerp between stops, so the wash renders as one
// continuous Windy-style gradient instead of hard posterised bands. Stops sit
// at the midpoints of the old bands, so the legend chips stay truthful.

Color _ramp(double v, List<(double, Color)> stops) {
  if (v.isNaN) return Colors.transparent;
  if (v <= stops.first.$1) return stops.first.$2;
  for (var k = 1; k < stops.length; k++) {
    if (v <= stops[k].$1) {
      final (v0, c0) = stops[k - 1];
      final (v1, c1) = stops[k];
      return Color.lerp(c0, c1, (v - v0) / (v1 - v0))!;
    }
  }
  return stops.last.$2;
}

// Soft low-end cutoff: alpha 0 below [lo], full above [hi] — washes fade in
// instead of snapping from transparent to full colour at a hard threshold.
double _fadeIn(double v, double lo, double hi) =>
    ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

Color _windColor(double mph) => _ramp(mph, const [
      (0.0,  Color(0xFFFFFFFF)),
      (3.5,  Color(0xFF98ECFF)),
      (7.5,  Color(0xFF4BCFFA)),
      (12.5, Color(0xFF56E39F)),
      (17.5, Color(0xFFF9CA24)),
      (22.5, Color(0xFFF0932B)),
      (30.0, Color(0xFFEB4D4B)),
      (42.0, Color(0xFF6C5CE7)),
    ]).withValues(alpha: 0.45);

Color _waveColor(double m) {
  final f = _fadeIn(m, 0.05, 0.3);
  if (f == 0) return Colors.transparent;
  return _ramp(m, const [
    (0.25, Color(0xFF7FB3D3)),
    (0.75, Color(0xFF2980B9)),
    (1.50, Color(0xFF1A5276)),
    (3.00, Color(0xFF0D2137)),
    (5.00, Color(0xFF07111E)),
  ]).withValues(alpha: 0.50 * f);
}

// Seas (NOAA WaveWatch III significant wave height, metres). A vivid
// StormSurf-style ramp — blue (calm) through green/yellow to red (big swell) —
// so offshore sea state reads clearly over the light basemap, where the Waves
// layer's subtle all-blue wash would wash out. Transparent over land/no-data.
Color _seasColor(double m) {
  if (!m.isFinite) return Colors.transparent;
  final f = _fadeIn(m, 0.05, 0.3);
  if (f == 0) return Colors.transparent;
  return _ramp(m, const [
    (0.30, Color(0xFF3A7BD5)), // calm — blue
    (0.75, Color(0xFF00B4D8)), // light chop — cyan
    (1.25, Color(0xFF2ECC71)), // building — green
    (1.75, Color(0xFFF1C40F)), // moderate — yellow
    (2.50, Color(0xFFF39C12)), // rough — orange
    (3.50, Color(0xFFE74C3C)), // high — red
    (5.00, Color(0xFF8E44AD)), // very high — purple
  ]).withValues(alpha: 0.60 * f);
}

// Cyan → indigo → purple → magenta: distinct hues that read clearly both
// on the map and as legend dots, and stand apart from the blue wave layer.
Color _swellColor(double m) {
  final f = _fadeIn(m, 0.05, 0.3);
  if (f == 0) return Colors.transparent;
  return _ramp(m, const [
    (0.25, Color(0xFF4DD0E1)),
    (0.75, Color(0xFF5C6BC0)),
    (1.50, Color(0xFF7E57C2)),
    (3.00, Color(0xFFAB47BC)),
    (5.00, Color(0xFFEC407A)),
  ]).withValues(alpha: 0.55 * f);
}

Color _rainColor(double mm) {
  final f = _fadeIn(mm, 0.05, 0.5);
  if (f == 0) return Colors.transparent;
  return _ramp(mm, const [
    (0.5,  Color(0xFFAED6F1)),
    (1.5,  Color(0xFF5DADE2)),
    (3.5,  Color(0xFF2E86C1)),
    (7.5,  Color(0xFF1A5276)),
    (15.0, Color(0xFF4A235A)),
  ]).withValues(alpha: 0.55 * f);
}

Color _tempColor(double degC) => _ramp(degC, const [
      (-7.5, Color(0xFF4A235A)),
      (-2.5, Color(0xFF1A5276)),
      (2.5,  Color(0xFF2E86C1)),
      (7.5,  Color(0xFFAED6F1)),
      (12.5, Color(0xFFA9DFBF)),
      (17.5, Color(0xFFF9E79F)),
      (22.5, Color(0xFFF9CA24)),
      (27.5, Color(0xFFF0932B)),
      (32.5, Color(0xFFEB4D4B)),
      (40.0, Color(0xFF922B21)),
    ]).withValues(alpha: 0.50);

// Keep the wash subtle — the isobar lines carry the detail.
Color _pressureColor(double hpa) => _ramp(hpa, const [
      (985.0,  Color(0xFF6C5CE7)),
      (995.0,  Color(0xFF4BCFFA)),
      (1004.0, Color(0xFF56E39F)),
      (1010.5, Color(0xFFFFFFFF)),
      (1015.5, Color(0xFFF9CA24)),
      (1020.5, Color(0xFFF0932B)),
      (1028.0, Color(0xFFEB4D4B)),
    ]).withValues(alpha: 0.28);

Color _cloudColor(double pct) {
  final t = (pct / 100.0).clamp(0.0, 1.0);
  if (t < 0.08) return Colors.transparent; // clear sky — no wash
  // Plain white clouds were nearly invisible on the light basemap. Ramp from a
  // light translucent gray (thin / high cirrus) to a dark, near-opaque slate
  // (overcast / storm anvils) so significant cover reads clearly. The pow()
  // curve lifts mid values, so building cloud shows before it's fully overcast.
  final e = math.pow(t, 0.7).toDouble();
  final r = (210 - e * (210 - 45)).round();
  final g = (216 - e * (216 - 55)).round();
  final b = (222 - e * (222 - 72)).round();
  final a = 0.32 + e * 0.56; // 0.32 (thin) → 0.88 (overcast/storm)
  return Color.fromARGB((a * 255).round(), r, g, b);
}

// ── Data model ────────────────────────────────────────────────────────────────

class _DataPoint {
  final double value;
  final double? direction;
  // Water fraction 0..1 — used by the Seas layer's land mask (1 = full data,
  // 0 = land/no model data). Defaults to 1 so all other layers are unaffected.
  final double coverage;
  const _DataPoint(this.value, [this.direction, this.coverage = 1.0]);
}

class _DataGrid {
  final List<_DataPoint> pts;
  final double latMin, lonMin, step;
  final int n;

  const _DataGrid(this.pts, this.latMin, this.lonMin, this.step, this.n);

  double get latMax => latMin + (n - 1) * step;
  double get lonMax => lonMin + (n - 1) * step;

  _DataPoint? _bilinear(double lat, double lon) {
    final fi = (lat - latMin) / step;
    final fj = (lon - lonMin) / step;
    final i0 = fi.floor(), j0 = fj.floor();
    final i1 = i0 + 1, j1 = j0 + 1;
    if (i0 < 0 || i1 >= n || j0 < 0 || j1 >= n) return null;
    final tx = fi - i0, ty = fj - j0;

    double val(int i, int j) => pts[i * n + j].value;
    final v = val(i0, j0) * (1 - tx) * (1 - ty) +
              val(i0, j1) * (1 - tx) * ty +
              val(i1, j0) * tx * (1 - ty) +
              val(i1, j1) * tx * ty;
    return _DataPoint(v, pts[i0 * n + j0].direction);
  }

  double primaryAt(double lat, double lon) =>
      _bilinear(lat, lon)?.value ?? 0;

  /// Bilinearly-interpolated water coverage (0..1) at a point — the Seas land
  /// mask. 0 outside the grid. Other layers leave coverage at 1 everywhere.
  double coverageAt(double lat, double lon) {
    final fi = (lat - latMin) / step;
    final fj = (lon - lonMin) / step;
    final i0 = fi.floor(), j0 = fj.floor();
    final i1 = i0 + 1, j1 = j0 + 1;
    if (i0 < 0 || i1 >= n || j0 < 0 || j1 >= n) return 0;
    final tx = fi - i0, ty = fj - j0;
    double c(int i, int j) => pts[i * n + j].coverage;
    return c(i0, j0) * (1 - tx) * (1 - ty) +
        c(i0, j1) * (1 - tx) * ty +
        c(i1, j0) * tx * (1 - ty) +
        c(i1, j1) * tx * ty;
  }

  /// Interpolated value + direction at a point (null if outside the grid).
  _DataPoint? pointAt(double lat, double lon) => _bilinear(lat, lon);

  (double, double)? uv(double lat, double lon) {
    final fi = (lat - latMin) / step;
    final fj = (lon - lonMin) / step;
    final i0 = fi.floor(), j0 = fj.floor();
    final i1 = i0 + 1, j1 = j0 + 1;
    if (i0 < 0 || i1 >= n || j0 < 0 || j1 >= n) return null;
    final tx = fi - i0, ty = fj - j0;

    double u(int i, int j) {
      final p = pts[i * n + j];
      if (p.direction == null) return 0;
      return p.value * -math.sin(p.direction! * math.pi / 180);
    }
    double v(int i, int j) {
      final p = pts[i * n + j];
      if (p.direction == null) return 0;
      return p.value * -math.cos(p.direction! * math.pi / 180);
    }
    double bil(double Function(int, int) f) =>
        f(i0, j0) * (1 - tx) * (1 - ty) +
        f(i0, j1) * (1 - tx) * ty +
        f(i1, j0) * tx * (1 - ty) +
        f(i1, j1) * tx * ty;

    return (bil(u), bil(v));
  }
}

// Bilinear sample of a regular native grid (e.g. NOAA WW3 0.5° cells) at an
// arbitrary lat/lon. `g[i][j]` is indexed from (lat0, lon0) with `step` spacing.
// Returns (value, coverage): the interpolation runs over only the non-NaN
// (water) corners, and `coverage` is the summed weight of those corners
// (1 = all four are water, 0 = all land). The caller uses coverage as a land
// mask so the wash fades out at the coast instead of bleeding inland.
(double, double) _sampleNative(List<List<double>> g, int nLat, int nLon,
    double lat0, double lon0, double step, double lat, double lon) {
  final fi = (lat - lat0) / step;
  final fj = (lon - lon0) / step;
  final i0 = fi.floor().clamp(0, nLat - 2);
  final j0 = fj.floor().clamp(0, nLon - 2);
  final tx = (fi - i0).clamp(0.0, 1.0);
  final ty = (fj - j0).clamp(0.0, 1.0);
  final corners = <(int, int, double)>[
    (i0, j0, (1 - tx) * (1 - ty)),
    (i0, j0 + 1, (1 - tx) * ty),
    (i0 + 1, j0, tx * (1 - ty)),
    (i0 + 1, j0 + 1, tx * ty),
  ];
  var sumV = 0.0, sumW = 0.0;
  for (final (i, j, w) in corners) {
    final x = g[i][j];
    if (!x.isNaN) {
      sumV += x * w;
      sumW += w;
    }
  }
  return (sumW > 0 ? sumV / sumW : 0.0, sumW);
}

// Renders a [field] to a smooth gradient image by sampling its bilinear
// interpolation at every pixel. Top-level so the prefetch path can reuse it.
// When [masked] (Seas/Waves/Swell), the per-point water coverage feathers the
// edge: fully transparent below ~0.4 coverage, ramping to full over 0.4–0.7 —
// a soft coastline with no colour bleeding onto land.
// [covWeighted] is for grids that store 0 at land points (the Open-Meteo
// marine layers): dividing the bilinear value by coverage undoes the dilution
// from those zero corners, so wave heights hold up right to the coast. The
// Seas grid already stores coverage-weighted values, so it leaves this off.
Future<ui.Image> _buildGradientImage(
    _DataGrid field, Color Function(double) colorFn,
    {int imgN = 128, bool masked = false, bool covWeighted = false}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  final latSpan = field.latMax - field.latMin;
  final lonSpan = field.lonMax - field.lonMin;
  for (var row = 0; row < imgN; row++) {
    for (var col = 0; col < imgN; col++) {
      final lat = field.latMax - (row / (imgN - 1)) * latSpan;
      final lon = field.lonMin + (col / (imgN - 1)) * lonSpan;
      var value = field.primaryAt(lat, lon);
      double feather = 1.0;
      if (masked) {
        final cov = field.coverageAt(lat, lon);
        if (cov < 0.4) continue; // land — leave transparent
        feather = ((cov - 0.4) / 0.3).clamp(0.0, 1.0); // soft coastline edge
        if (covWeighted) value /= cov;
      }
      var color = colorFn(value);
      if (feather < 1.0) color = color.withValues(alpha: color.a * feather);
      c.drawRect(
        Rect.fromLTWH(col.toDouble(), row.toDouble(), 1, 1),
        Paint()..color = color,
      );
    }
  }
  final pict = recorder.endRecording();
  return pict.toImage(imgN, imgN);
}

// ── Prefetch (warm the map before it opens) ──────────────────────────────────
// When the user taps the weather-map (wind) icon we kick off the default Wind
// layer's data + the basemap tiles around the station, so the map paints
// immediately instead of showing a spinner over grey tiles.
final _prefetchDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 12),
  receiveTimeout: const Duration(seconds: 15),
));
final _prefetchCache =
    <String, ({_DataGrid field, ui.Image image, DateTime fetchedAt})>{};
String _prefetchKey(double lat, double lon) =>
    'wind_${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}';

int _tileX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
int _tileY(double lat, int z) {
  final r = lat * math.pi / 180;
  return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z))
      .floor();
}

// Fetches the Wind grid (Open-Meteo current wind) for a geometry and renders
// it. Shared by the prefetch path and could be reused elsewhere.
Future<({_DataGrid field, ui.Image image})?> _fetchWindGrid(
    Dio dio, double latMin, double lonMin, double step, int n) async {
  final lats = <String>[], lons = <String>[];
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      lats.add((latMin + i * step).toStringAsFixed(4));
      lons.add((lonMin + j * step).toStringAsFixed(4));
    }
  }
  final resp = await dio.get('https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': lats.join(','),
        'longitude': lons.join(','),
        'current': 'wind_speed_10m,wind_direction_10m',
        'wind_speed_unit': 'mph',
        'forecast_days': '1',
      });
  final items = resp.data as List;
  if (items.isEmpty || items[0]['current'] == null) return null;
  final pts = items.map<_DataPoint>((item) {
    final c = item['current'] as Map? ?? {};
    return _DataPoint((c['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
        (c['wind_direction_10m'] as num?)?.toDouble());
  }).toList();
  final field = _DataGrid(pts, latMin, lonMin, step, n);
  return (field: field, image: await _buildGradientImage(field, _windColor));
}

/// Warms the Wind grid + basemap tiles for [lat]/[lon] so the weather map opens
/// smoothly. Fire-and-forget; safe to call repeatedly (cached, deduped by TTL).
void prefetchWindMap(double lat, double lon, BuildContext context) {
  final key = _prefetchKey(lat, lon);
  final cached = _prefetchCache[key];
  if (cached == null ||
      DateTime.now().difference(cached.fetchedAt) > const Duration(minutes: 20)) {
    () async {
      try {
        const span = 14.0, n = 9; // ≈ the zoom-8 initial view
        final g = await _fetchWindGrid(
            _prefetchDio, lat - span / 2, lon - span / 2, span / (n - 1), n);
        if (g != null) {
          _prefetchCache[key] =
              (field: g.field, image: g.image, fetchedAt: DateTime.now());
        }
      } catch (_) {/* best-effort */}
    }();
  }
  // Warm the CARTO basemap tiles (z7–9, 3×3 around the station).
  () async {
    try {
      for (final z in [7, 8, 9]) {
        final cx = _tileX(lon, z), cy = _tileY(lat, z);
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            if (!context.mounted) return;
            final url = 'https://a.basemaps.cartocdn.com/rastertiles/voyager/'
                '$z/${cx + dx}/${cy + dy}@2x.png';
            precacheImage(NetworkImage(url), context).catchError((_) {});
          }
        }
      }
    } catch (_) {/* best-effort */}
  }();
}

// ── Layer system ───────────────────────────────────────────────────────────────

enum _Layer { wind, waves, swell, seas, rain, temp, pressure, clouds }


class _LayerDef {
  final String label;
  final IconData icon;
  final bool isMarine;
  final bool hasFlow;
  final bool hasIsobars;
  final bool isRadar; // overlay live weather-radar tiles instead of a grid
  final bool isSatellite; // overlay live GOES satellite tiles instead of a grid
  final bool isSeas; // animated NOAA WaveWatch III forecast (own timeline)
  final String valueVar;
  final String? directionVar;
  final Color Function(double) colorFn;
  final List<(Color, String)> legend;       // Standard (imperial) labels
  final List<(Color, String)>? legendMetric; // Metric labels (null = same)
  const _LayerDef({
    required this.label,
    required this.icon,
    required this.isMarine,
    required this.hasFlow,
    this.hasIsobars = false,
    this.isRadar = false,
    this.isSatellite = false,
    this.isSeas = false,
    required this.valueVar,
    this.directionVar,
    required this.colorFn,
    required this.legend,
    this.legendMetric,
  });

  List<(Color, String)> legendFor(bool metric) =>
      (metric && legendMetric != null) ? legendMetric! : legend;
}

const _kLayers = <_Layer, _LayerDef>{
  _Layer.wind: _LayerDef(
    label: 'Wind', icon: Icons.air,
    isMarine: false, hasFlow: true,
    valueVar: 'wind_speed_10m', directionVar: 'wind_direction_10m',
    colorFn: _windColor,
    legend: [
      (Color(0xFF98ECFF), '<5'),
      (Color(0xFF56E39F), '5–15'),
      (Color(0xFFF9CA24), '15–25'),
      (Color(0xFFEB4D4B), '>25 mph'),
    ],
    legendMetric: [
      (Color(0xFF98ECFF), '<8'),
      (Color(0xFF56E39F), '8–24'),
      (Color(0xFFF9CA24), '24–40'),
      (Color(0xFFEB4D4B), '>40 km/h'),
    ],
  ),
  _Layer.waves: _LayerDef(
    label: 'Waves', icon: Icons.waves,
    isMarine: true, hasFlow: true,
    valueVar: 'wave_height', directionVar: 'wave_direction',
    colorFn: _waveColor,
    legend: [
      (Color(0xFF7FB3D3), '<1.5'),
      (Color(0xFF2980B9), '1.5–3'),
      (Color(0xFF1A5276), '3–6'),
      (Color(0xFF0D2137), '>6 ft'),
    ],
    legendMetric: [
      (Color(0xFF7FB3D3), '<0.5m'),
      (Color(0xFF2980B9), '0.5–1m'),
      (Color(0xFF1A5276), '1–2m'),
      (Color(0xFF0D2137), '>2m'),
    ],
  ),
  _Layer.swell: _LayerDef(
    label: 'Swell', icon: Icons.sailing,
    isMarine: true, hasFlow: true,
    valueVar: 'swell_wave_height', directionVar: 'swell_wave_direction',
    colorFn: _swellColor,
    legend: [
      (Color(0xFF4DD0E1), '<1.5'),
      (Color(0xFF5C6BC0), '1.5–3'),
      (Color(0xFF7E57C2), '3–6'),
      (Color(0xFFAB47BC), '>6 ft'),
    ],
    legendMetric: [
      (Color(0xFF4DD0E1), '<0.5m'),
      (Color(0xFF5C6BC0), '0.5–1m'),
      (Color(0xFF7E57C2), '1–2m'),
      (Color(0xFFAB47BC), '>2m'),
    ],
  ),
  // NOAA WaveWatch III significant wave height — animated offshore forecast.
  // Same units/colours as the Waves layer (metres), but model-sourced from NOAA
  // and stepped through the forecast like StormSurf's Gulf sea-height map.
  _Layer.seas: _LayerDef(
    label: 'Seas (WW3)', icon: Icons.tsunami,
    isMarine: true, hasFlow: false, isSeas: true,
    valueVar: 'Thgt',
    colorFn: _seasColor,
    legend: [
      (Color(0xFF3A7BD5), '<3'),
      (Color(0xFF2ECC71), '3–5'),
      (Color(0xFFF39C12), '6–10'),
      (Color(0xFFE74C3C), '>10 ft'),
    ],
    legendMetric: [
      (Color(0xFF3A7BD5), '<1'),
      (Color(0xFF2ECC71), '1–1.5'),
      (Color(0xFFF39C12), '2–3'),
      (Color(0xFFE74C3C), '>3m'),
    ],
  ),
  _Layer.rain: _LayerDef(
    label: 'Rain', icon: Icons.radar,
    isMarine: false, hasFlow: false, isRadar: true,
    valueVar: 'precipitation', colorFn: _rainColor,
    legend: [
      (Color(0xFF6FCF52), 'Light'),
      (Color(0xFFE6E600), 'Moderate'),
      (Color(0xFFF0932B), 'Heavy'),
      (Color(0xFFEB4D4B), 'Intense'),
    ],
  ),
  _Layer.temp: _LayerDef(
    label: 'Temperature', icon: Icons.thermostat,
    isMarine: false, hasFlow: false,
    valueVar: 'temperature_2m', colorFn: _tempColor,
    legend: [
      (Color(0xFF2E86C1), '<50'),
      (Color(0xFFA9DFBF), '50–68'),
      (Color(0xFFF9CA24), '68–86'),
      (Color(0xFFEB4D4B), '>86°F'),
    ],
    legendMetric: [
      (Color(0xFF2E86C1), '<10'),
      (Color(0xFFA9DFBF), '10–20'),
      (Color(0xFFF9CA24), '20–30'),
      (Color(0xFFEB4D4B), '>30°C'),
    ],
  ),
  _Layer.pressure: _LayerDef(
    label: 'Pressure', icon: Icons.speed,
    isMarine: false, hasFlow: false, hasIsobars: true,
    valueVar: 'pressure_msl', colorFn: _pressureColor,
    legend: [
      (Color(0xFF6C5CE7), '<1000'),
      (Color(0xFF56E39F), '1000–1013'),
      (Color(0xFFF9CA24), '1013–1020'),
      (Color(0xFFEB4D4B), '>1020 hPa'),
    ],
  ),
  _Layer.clouds: _LayerDef(
    label: 'Clouds', icon: Icons.cloud,
    isMarine: false, hasFlow: false, isSatellite: true,
    valueVar: 'cloud_cover', colorFn: _cloudColor,
    // Live GOES-East infrared: cloud-top temperature. Warm/low cloud is grey;
    // colder, taller cloud (building storms → anvils) ramps green→yellow→red.
    legend: [
      (Color(0xCCBFC7CF), 'Low'),
      (Color(0xCC56E39F), 'Mid'),
      (Color(0xCCF9CA24), 'Tall'),
      (Color(0xCCEB4D4B), 'Storm tops'),
    ],
  ),
};

// ── Smooth gradient layer ─────────────────────────────────────────────────────

class _SmoothGradientLayer extends StatelessWidget {
  final _DataGrid field;
  final ui.Image image;
  const _SmoothGradientLayer(
      {required this.field, required this.image});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SmoothGradientPainter(field, image, MapCamera.of(context)),
        child: const SizedBox.expand(),
      );
}

class _SmoothGradientPainter extends CustomPainter {
  final _DataGrid field;
  final ui.Image image;
  final MapCamera camera;
  _SmoothGradientPainter(this.field, this.image, this.camera);

  @override
  void paint(Canvas canvas, Size size) {
    final nw = camera.latLngToScreenPoint(LatLng(field.latMax, field.lonMin));
    final se = camera.latLngToScreenPoint(LatLng(field.latMin, field.lonMax));
    canvas.drawImageRect(
      image,
      // Source is the whole rendered gradient image (built at a fixed pixel
      // size in _buildGradientImage), not field.n — sampling only an n×n corner
      // would stretch a sliver of the data across the whole overlay.
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTRB(nw.x.toDouble(), nw.y.toDouble(),
                    se.x.toDouble(), se.y.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SmoothGradientPainter old) =>
      old.image != image || old.camera != camera;
}

// ── Isobars (pressure contour lines, Windy-style) ─────────────────────────────

class _IsobarLayer extends StatelessWidget {
  final _DataGrid field;
  const _IsobarLayer({required this.field});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _IsobarPainter(field, MapCamera.of(context)),
        child: const SizedBox.expand(),
      );
}

class _IsobarPainter extends CustomPainter {
  final _DataGrid field;
  final MapCamera camera;
  _IsobarPainter(this.field, this.camera);

  Offset _s(double lat, double lon) {
    final p = camera.latLngToScreenPoint(LatLng(lat, lon));
    return Offset(p.x.toDouble(), p.y.toDouble());
  }

  @override
  void paint(Canvas canvas, Size size) {
    const r = 48; // fine sampling resolution for smooth contours
    final dLat = (field.latMax - field.latMin) / r;
    final dLon = (field.lonMax - field.lonMin) / r;

    // Sample the interpolated field on a fine grid.
    final v = List.generate(
        r + 1, (i) => List<double>.filled(r + 1, 0.0), growable: false);
    var vmin = double.infinity, vmax = -double.infinity;
    for (var i = 0; i <= r; i++) {
      final lat = field.latMin + i * dLat;
      for (var j = 0; j <= r; j++) {
        final val = field.primaryAt(lat, field.lonMin + j * dLon);
        v[i][j] = val;
        if (val < vmin) vmin = val;
        if (val > vmax) vmax = val;
      }
    }
    if (!(vmax > vmin)) return;

    // Contour interval: at most 1 hPa so isobars stay dense even in calm
    // conditions, finer if the range is tiny.
    final raw = (vmax - vmin) / 5;
    final step = raw <= 0.25 ? 0.25 : raw <= 0.5 ? 0.5 : 1.0;
    final start = (vmin / step).ceilToDouble() * step;
    final labelDecimals = step < 1 ? 1 : 0;

    // Thin, clean isobars: a hairline dark contour with a soft light halo for
    // legibility on the light basemap (no thick double-stroke that reads as
    // "railroad tracks").
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.55);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.62);

    final rect = Offset.zero & size;
    final placedLabels = <Offset>[];
    final pendingLabels = <(Offset, String)>[];
    // Accumulate every contour segment into one path, then stroke the whole
    // thing in a single pass — so the halo never over-paints (nicks) a line
    // joint and the isobars read as continuous, unbroken curves.
    final path = ui.Path();

    for (var level = start; level <= vmax; level += step) {
      var labelPlacedForLevel = false;
      for (var i = 0; i < r; i++) {
        final lat0 = field.latMin + i * dLat;
        final lat1 = lat0 + dLat;
        for (var j = 0; j < r; j++) {
          final lon0 = field.lonMin + j * dLon;
          final lon1 = lon0 + dLon;
          // Cell corners: A=NW-ish (i,j), B=(i,j+1), C=(i+1,j+1), D=(i+1,j)
          final a = v[i][j], b = v[i][j + 1], c = v[i + 1][j + 1], d = v[i + 1][j];

          final crossings = <Offset>[];
          void edge(double la0, double lo0, double e0, double la1, double lo1,
              double e1) {
            if ((e0 - level) * (e1 - level) < 0) {
              final t = (level - e0) / (e1 - e0);
              crossings.add(
                  _s(la0 + (la1 - la0) * t, lo0 + (lo1 - lo0) * t));
            }
          }

          edge(lat0, lon0, a, lat0, lon1, b); // top
          edge(lat0, lon1, b, lat1, lon1, c); // right
          edge(lat1, lon1, c, lat1, lon0, d); // bottom
          edge(lat1, lon0, d, lat0, lon0, a); // left

          if (crossings.length >= 2) {
            path.moveTo(crossings[0].dx, crossings[0].dy);
            path.lineTo(crossings[1].dx, crossings[1].dy);
            if (crossings.length == 4) {
              path.moveTo(crossings[2].dx, crossings[2].dy);
              path.lineTo(crossings[3].dx, crossings[3].dy);
            }

            // Label this level once, spaced out from other labels.
            if (!labelPlacedForLevel) {
              final mid = Offset((crossings[0].dx + crossings[1].dx) / 2,
                  (crossings[0].dy + crossings[1].dy) / 2);
              if (rect.contains(mid) &&
                  placedLabels.every((p) => (p - mid).distance > 70)) {
                pendingLabels.add((mid, level.toStringAsFixed(labelDecimals)));
                placedLabels.add(mid);
                labelPlacedForLevel = true;
              }
            }
          }
        }
      }
    }

    // Stroke all isobars in one pass (halo first, hairline on top) so lines are
    // continuous, then draw the number chips last so no line crosses over them.
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
    for (final (at, text) in pendingLabels) {
      _label(canvas, at, text);
    }
  }

  void _label(Canvas canvas, Offset at, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pill = Rect.fromCenter(
        center: at, width: tp.width + 12, height: tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(8)),
      Paint()..color = Colors.black.withValues(alpha: 0.82),
    );
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_IsobarPainter old) =>
      old.field != field || old.camera != camera;
}

// ── Particle ──────────────────────────────────────────────────────────────────

class _Particle {
  double lat, lon;
  int age = 0;
  final List<(double, double)> trail = [];

  static const trailLen = 20;
  static const maxAge   = 220;

  _Particle(this.lat, this.lon);

  factory _Particle.random(
          math.Random rng, double s, double n, double w, double e) =>
      _Particle(s + rng.nextDouble() * (n - s),
                w + rng.nextDouble() * (e - w));

  void step(_DataGrid field, double dt) {
    trail.add((lat, lon));
    if (trail.length > trailLen) trail.removeAt(0);

    final uv = field.uv(lat, lon);
    if (uv == null) { age = maxAge; return; }
    final (u, v) = uv;

    const k = 0.447 / 111000 * 8000;
    lat += v * k * dt;
    lon += u * k * dt / math.max(0.1, math.cos(lat * math.pi / 180));
    age++;
  }

  double get opacity {
    const fi = 25, fo = 40;
    if (age < fi) return age / fi;
    if (age > maxAge - fo) return (maxAge - age) / fo;
    return 1.0;
  }
}

// ── Particle layer ─────────────────────────────────────────────────────────────

class _WindParticleLayer extends StatefulWidget {
  final _DataGrid? field;
  final Color Function(double) colorFn;
  final bool skipEmpty; // for marine layers: no particles where value ≈ 0 (land)
  const _WindParticleLayer(
      {required this.field,
      required this.colorFn,
      this.skipEmpty = false});

  @override
  State<_WindParticleLayer> createState() => _WindParticleLayerState();
}

class _WindParticleLayerState extends State<_WindParticleLayer>
    with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  final _rng = math.Random();
  late final Ticker _ticker;
  Duration? _lastTick;
  static const _maxParticles = 600;
  // Repaint signal for the painter — lets the Ticker drive the canvas without a
  // full widget rebuild (setState) every frame. Bumped once per tick.
  final _repaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted || widget.field == null) return;
    final dt = _lastTick == null
        ? 0.016
        : (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final camera = MapCamera.of(context);
    final b = camera.visibleBounds;
    const pad = 0.5;
    const empty = 0.05;

    for (final p in _particles) {
      p.step(widget.field!, dt.clamp(0.005, 0.05));
      // Marine layers: retire particles that drift onto land (no wave data).
      if (widget.skipEmpty &&
          widget.field!.primaryAt(p.lat, p.lon) < empty) {
        p.age = _Particle.maxAge;
      }
    }

    _particles.removeWhere((p) =>
        p.age >= _Particle.maxAge ||
        p.lat < b.south - pad || p.lat > b.north + pad ||
        p.lon < b.west  - pad || p.lon > b.east  + pad);

    // Refill, but for marine layers only spawn where there is actually water.
    var guard = 0;
    while (_particles.length < _maxParticles && guard < _maxParticles * 3) {
      guard++;
      final p = _Particle.random(_rng, b.south, b.north, b.west, b.east);
      if (widget.skipEmpty &&
          widget.field!.primaryAt(p.lat, p.lon) < empty) {
        continue; // landed on land — try another spot
      }
      _particles.add(p);
    }

    // Repaint the canvas only — no widget rebuild. The painter reads the live
    // _particles list, so the mutated positions show on the next frame.
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          // Live list + repaint Listenable: animation frames repaint just the
          // canvas; only a real camera change (pan/zoom) rebuilds for the new
          // projection.
          painter: _ParticlePainter(_particles, MapCamera.of(context),
              widget.field, widget.colorFn, _repaint),
          child: const SizedBox.expand(),
        ),
      );
}

// ── Particle painter ──────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final MapCamera camera;
  final _DataGrid? field;
  final Color Function(double) colorFn;
  _ParticlePainter(this.particles, this.camera, this.field, this.colorFn,
      Listenable repaint)
      : super(repaint: repaint);

  Offset _s(double lat, double lon) {
    final pt = camera.latLngToScreenPoint(LatLng(lat, lon));
    return Offset(pt.x.toDouble(), pt.y.toDouble());
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (field == null) return;
    final linePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final p in particles) {
      final uv = field!.uv(p.lat, p.lon);
      if (uv == null) continue;
      final (u, v) = uv;
      final speed = math.sqrt(u * u + v * v);
      final base = colorFn(speed);
      // Transparent = "no data here" (e.g. waves over land). Don't draw —
      // otherwise the alpha blend below would paint a black dot.
      if (base.a == 0) continue;

      final allPts = [
        ...p.trail.map((t) => _s(t.$1, t.$2)),
        _s(p.lat, p.lon),
      ];

      for (var i = 1; i < allPts.length; i++) {
        final frac = i / allPts.length;
        canvas.drawLine(
          allPts[i - 1],
          allPts[i],
          linePaint
            ..color = base.withValues(alpha: (frac * p.opacity * 0.95).clamp(0, 1))
            ..strokeWidth = 0.5 + frac * 1.8,
        );
      }

      if (allPts.isNotEmpty) {
        canvas.drawCircle(allPts.last, 2.0,
            Paint()..color = base.withValues(alpha: p.opacity));
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter _) => true;
}

// ── Layer picker bottom sheet ─────────────────────────────────────────────────

class _LayerPicker extends StatelessWidget {
  final _Layer current;
  final void Function(_Layer) onSelect;
  const _LayerPicker({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: kNavyLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('MAP LAYER',
                    style: TextStyle(
                        color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
            ..._Layer.values.map((layer) {
              final def = _kLayers[layer]!;
              final selected = layer == current;
              return ListTile(
                dense: true,
                leading: Icon(def.icon,
                    color: selected ? kCyan : Colors.white54, size: 20),
                title: Text(def.label,
                    style: TextStyle(
                        color: selected ? kCyan : Colors.white,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal)),
                trailing: selected
                    ? const Icon(Icons.check, color: kCyan, size: 18)
                    : null,
                onTap: () => onSelect(layer),
              );
            }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
}

// ── Radar frame ────────────────────────────────────────────────────────────────

class _RadarFrame {
  final int time;        // epoch seconds
  final String template; // tile URL template
  final bool nowcast;    // true = forecast frame
  const _RadarFrame(this.time, this.template, this.nowcast);
}

// ── Blend-mode wrapper ────────────────────────────────────────────────────────
// Composites its child onto the layers below using a blend mode. Used to screen-
// blend the GOES satellite overlay so black (clear-sky) pixels read as
// transparent and only cloud/storm-top brightness shows over the basemap.

class _BlendMask extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;
  const _BlendMask({required this.blendMode, required Widget super.child});

  @override
  _RenderBlendMask createRenderObject(BuildContext context) =>
      _RenderBlendMask(blendMode);

  @override
  void updateRenderObject(BuildContext context, _RenderBlendMask obj) {
    obj.blendMode = blendMode;
  }
}

class _RenderBlendMask extends RenderProxyBox {
  BlendMode blendMode;
  _RenderBlendMask(this.blendMode);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.saveLayer(offset & size, Paint()..blendMode = blendMode);
    super.paint(context, offset);
    context.canvas.restore();
  }
}

// ── Hourly forecast strip data ────────────────────────────────────────────────

class _HourForecast {
  final DateTime time;
  final double tempC;
  final int precipPct;
  final int weatherCode;
  const _HourForecast({
    required this.time,
    required this.tempC,
    required this.precipPct,
    required this.weatherCode,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class WindMapScreen extends ConsumerStatefulWidget {
  final double lat;
  final double lon;
  final String stationName;

  const WindMapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.stationName,
  });

  @override
  ConsumerState<WindMapScreen> createState() => _WindMapScreenState();
}

class _WindMapScreenState extends ConsumerState<WindMapScreen> {
  final _mapController = MapController();
  _Layer _currentLayer = _Layer.wind;
  _DataGrid? _field;
  ui.Image? _gradientImage;
  bool _loading = true;
  String? _error;
  // The map centre, tracked live as you pan — the centre reticle reads the
  // value here (Windy-style), so there's no tap-to-place probe dot anymore.
  LatLng? _probe;
  // The point the readout samples: the live centre, falling back to the station
  // before the first camera frame / right after a layer switch (map is recentred
  // on the station then, so the station IS the centre).
  LatLng get _readPoint => _probe ?? LatLng(widget.lat, widget.lon);
  Timer? _moveDebounce;
  // Recenter button shows once the station pin pans off-centre; the pin stays
  // anchored, this just snaps the camera back. Toggled only by panning.
  bool _showRecenter = false;
  // Radar animation (rain layer): NOAA WMS frames (past) + forecast overlays.
  List<_RadarFrame> _radarFrames = [];
  int _radarIndex = 0;
  bool _radarPlaying = true;
  Timer? _radarAnim;
  // Pre-fetched radar frame images (one composited GetMap PNG per frame) +
  // the geographic bounds they cover. Pre-caching these makes playback smooth
  // (swapping decoded images) instead of re-tiling the WMS on every frame.
  List<String> _radarImageUrls = [];
  LatLngBounds? _radarBounds;
  // Forecast overlay: Open-Meteo hourly precipitation grids (auto-loaded).
  List<_DataGrid> _forecastGrids = [];
  List<ui.Image?> _forecastImages = [];
  List<DateTime> _forecastTimes = [];
  int _radarPastCount = 0; // how many _radarFrames entries are observed (not nowcast)
  // Seas (NOAA WaveWatch III): animated significant-wave-height forecast frames,
  // each a pre-rendered gradient over its own _DataGrid. Own simple timeline.
  List<({DateTime time, _DataGrid grid, ui.Image image})> _seasFrames = [];
  int _seasIndex = 0;
  bool _seasPlaying = true;
  Timer? _seasAnim;
  // Hourly strip: single-point forecast for the bottom panel.
  List<_HourForecast> _hourlyStrip = [];
  // Stale-data support: when Open-Meteo is down, show the last good grid.
  DateTime? _staleDataTime; // non-null = currently showing cached data
  static final _gridCache =
      <_Layer, ({_DataGrid field, ui.Image image, DateTime fetchedAt})>{};

  // Per-session (this map instance) grid cache, so re-selecting a layer paints
  // instantly then refines. Instance-scoped, so it's always this station's data.
  final _sessionGrids =
      <_Layer, ({_DataGrid field, ui.Image image, DateTime fetchedAt})>{};
  bool _firstLoad = true; // first grid fetch can paint a prefetched grid

  double _initialZoom(_Layer l) => l == _Layer.pressure
      ? 6.0
      : l == _Layer.clouds
          ? 6.0
          : l == _Layer.seas
              ? 6.5
              : l == _Layer.rain
                  ? 7.0
                  : 8.0;

  // ── Unified frame helpers ─────────────────────────────────────────────────
  int get _totalFrames => _radarFrames.length + _forecastGrids.length;
  bool _isRadarFrame(int i) => i < _radarFrames.length;
  bool _isNowcastFrame(int i) =>
      i >= _radarPastCount && i < _radarFrames.length;
  int _forecastFrameIdx(int i) => i - _radarFrames.length;

  static const _n = 9;
  static const _seasN = 24; // upsample WW3 0.5° onto a finer grid for smoothness
  // Grid span = view span × this margin. Wide enough that ordinary pans stay
  // inside the fetched grid (no refetch), without costing much resolution.
  static const _kGridMargin = 1.45;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  @override
  void initState() {
    super.initState();
    // Fetch once the map has laid out, so we can size the grid to the view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchGrid();
    });
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    _radarAnim?.cancel();
    _seasAnim?.cancel();
    super.dispose();
  }

  // Re-fetch (quietly) when the user pans/zooms so the overlay always covers
  // the visible area — like Windy, the data follows the map.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    // Live centre readout: keep _probe pinned to the map centre so the reticle's
    // value updates as you pan. Cheap — it just resamples the in-memory grid.
    if (_field != null && camera.center != _probe) {
      setState(() => _probe = camera.center);
    }
    if (!hasGesture) return;
    final off =
        MapRecenterButton.offCenter(camera, LatLng(widget.lat, widget.lon));
    if (off != _showRecenter) setState(() => _showRecenter = off);
    final cur = _kLayers[_currentLayer]!;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      // Radar and clouds use pre-fetched overlay images, so rebuild them for
      // the new view (data follows the map, like the grid layers).
      if (cur.isRadar) {
        _fetchRadar();
      } else if (cur.isSatellite) {
        _fetchSatellite();
      } else {
        // Small pans/zooms reuse the in-hand grid: skip the refetch while the
        // view is still inside the grid AND a fresh grid wouldn't be ~2× finer
        // — no flicker, no API chatter while exploring nearby water.
        final f = _field;
        if (f != null) {
          final vb = _mapController.camera.visibleBounds;
          final viewSpan = math.max(vb.north - vb.south, vb.east - vb.west);
          final covered = vb.north <= f.latMax && vb.south >= f.latMin &&
              vb.east <= f.lonMax && vb.west >= f.lonMin;
          final fineEnough = viewSpan * _kGridMargin >
              (f.latMax - f.latMin) * 0.55;
          if (covered && fineEnough) return;
        }
        _fetchGrid(silent: true);
      }
    });
  }

  Future<void> _fetchGrid({_Layer? layer, bool silent = false}) async {
    final l = layer ?? _currentLayer;
    final def = _kLayers[l]!;

    // Instant paint from a warm grid (no spinner), then refine silently — uses
    // this session's cache for layer re-selects, and the prefetch cache (warmed
    // when the wind icon was tapped) for the very first Wind load.
    if (!silent && !def.isRadar && !def.isSatellite && !def.isSeas) {
      final firstWind = _firstLoad && l == _Layer.wind;
      _firstLoad = false;
      final warm = _sessionGrids[l] ??
          (firstWind ? _prefetchCache[_prefetchKey(widget.lat, widget.lon)] : null);
      if (warm != null &&
          DateTime.now().difference(warm.fetchedAt) <
              const Duration(minutes: 30)) {
        if (layer != null) {
          _mapController.move(LatLng(widget.lat, widget.lon), _initialZoom(l));
        }
        setState(() {
          _currentLayer = l;
          _field = warm.field;
          _gradientImage = warm.image;
          _loading = false;
          _error = null;
          _probe = null;
          _staleDataTime = null;
        });
        return _fetchGrid(silent: true); // refine to the exact view
      }
    }

    if (!silent) {
      _radarAnim?.cancel();
      setState(() {
        _loading = true; _error = null; _staleDataTime = null;
        _field = null; _gradientImage = null; _probe = null;
        _radarFrames = []; _radarPastCount = 0;
        _radarImageUrls = []; _radarBounds = null;
        _forecastGrids = []; _forecastImages = []; _forecastTimes = [];
        _hourlyStrip = [];
        _seasAnim?.cancel(); _seasFrames = []; _seasIndex = 0;
      });
    }
    if (layer != null) {
      setState(() { _currentLayer = layer; _staleDataTime = null; });
      // Pressure is a synoptic-scale field — zoom out so isobars are visible,
      // like Windy. Seas (offshore WW3) also opens wide so the open Gulf fills
      // the view. Other layers recenter on the station at a local view.
      // Pressure/Seas open wide (synoptic / offshore); others recenter local.
      _mapController.move(LatLng(widget.lat, widget.lon), _initialZoom(layer));
    }

    // Rain uses live weather-radar tiles rather than a sampled grid.
    if (def.isRadar) {
      await _fetchRadar();
      return;
    }

    // Seas is the animated NOAA WaveWatch III forecast (its own timeline).
    if (def.isSeas) {
      await _fetchSeas(silent: silent);
      return;
    }

    // Clouds is an animated GOES satellite tile layer (its own timeline).
    if (def.isSatellite) {
      _fetchSatellite();
      return;
    }

    // Size a square grid to cover the current view (wider dimension) + margin.
    final cam = _mapController.camera;
    final b = cam.visibleBounds;
    final span = math.max(b.north - b.south, b.east - b.west) * _kGridMargin;
    final step = span / (_n - 1);
    final latMin = cam.center.latitude - span / 2;
    final lonMin = cam.center.longitude - span / 2;

    final lats = <String>[], lons = <String>[];
    for (var i = 0; i < _n; i++) {
      for (var j = 0; j < _n; j++) {
        lats.add((latMin + i * step).toStringAsFixed(4));
        lons.add((lonMin + j * step).toStringAsFixed(4));
      }
    }

    final currentVars = def.directionVar != null
        ? '${def.valueVar},${def.directionVar}'
        : def.valueVar;

    final baseUrl = def.isMarine
        ? 'https://marine-api.open-meteo.com/v1/marine'
        : 'https://api.open-meteo.com/v1/forecast';

    try {
      final resp = await _dio.get(baseUrl, queryParameters: {
        'latitude':  lats.join(','),
        'longitude': lons.join(','),
        'current':   currentVars,
        if (!def.isMarine) 'wind_speed_unit': 'mph',
        if (!def.isMarine) 'forecast_days': '1',
      });

      final items = resp.data as List;
      if (items.isEmpty || items[0]['current'] == null) {
        if (mounted && !silent) {
          setState(() {
            _error = def.isMarine
                ? 'No ${def.label.toLowerCase()} data at this location'
                : 'No data available';
            _loading = false;
          });
        }
        return;
      }

      final pts = items.map<_DataPoint>((item) {
        final c = item['current'] as Map? ?? {};
        final raw = c[def.valueVar] as num?;
        final d = def.directionVar != null
            ? (c[def.directionVar!] as num?)?.toDouble()
            : null;
        // Marine variables come back null over land — record that as zero
        // water coverage so the render can mask the wash to the sea.
        return _DataPoint(raw?.toDouble() ?? 0.0, d,
            (def.isMarine && raw == null) ? 0.0 : 1.0);
      }).toList();

      final field = _DataGrid(pts, latMin, lonMin, step, _n);
      // Marine washes are land-masked (192px for a crisper coastline edge).
      final img = def.isMarine
          ? await _buildGradientImage(field, def.colorFn,
              imgN: 192, masked: true, covWeighted: true)
          : await _buildGradientImage(field, def.colorFn);

      if (mounted) {
        final entry = (field: field, image: img, fetchedAt: DateTime.now());
        _gridCache[_currentLayer] = entry;
        _sessionGrids[_currentLayer] = entry; // instant on re-select
        setState(() {
          _field = field;
          _gradientImage = img;
          _staleDataTime = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || silent) return;
      // Try to show the last cached grid rather than a blank error screen.
      final cached = _gridCache[_currentLayer];
      if (cached != null) {
        setState(() {
          _field = cached.field;
          _gradientImage = cached.image;
          _staleDataTime = cached.fetchedAt;
          _loading = false;
        });
      } else {
        // No cache — show a descriptive error message.
        final String msg;
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout) {
            msg = 'Request timed out — check your connection';
          } else if ((e.type == DioExceptionType.badResponse &&
                      (e.response?.statusCode ?? 0) >= 500) ||
                     e.type == DioExceptionType.connectionError) {
            msg = 'Open-Meteo is temporarily down — try again in a few minutes';
          } else {
            msg = 'Could not load weather data';
          }
        } else {
          msg = 'Could not load weather data';
        }
        setState(() { _error = msg; _loading = false; });
      }
    }
  }

  // lat/lon → EPSG:3857 (Web Mercator) metres, matching the map projection so
  // a GetMap image aligns 1:1 when placed on its LatLngBounds.
  (double, double) _toMercator(double lat, double lon) {
    const r = 20037508.34;
    final x = lon * r / 180.0;
    final y = math.log(math.tan((90 + lat) * math.pi / 360.0)) /
        (math.pi / 180.0) * r / 180.0;
    return (x, y);
  }

  // Live precipitation radar from NOAA MRMS composite reflectivity
  // (conus_cref_qcd) via WMS — free, no key, US coverage, ~2 min cadence and
  // full-resolution detail (same mosaic the major weather apps render).
  //
  // Each frame is fetched as a single composited GetMap PNG covering the
  // visible area (+ margin) and pre-cached, so animation swaps pre-decoded
  // images instead of re-tiling the WMS per frame — which caused the
  // stop-and-go playback. GeoServer's time dimension uses nearestValue="1",
  // so approximate timestamps over the past ~2h snap to the closest real
  // frame. `_RadarFrame.template` holds the ISO-8601 time string.
  Future<void> _fetchRadar() async {
    final now = DateTime.now().toUtc();
    final frames = <_RadarFrame>[];
    // 13 frames at 10-min spacing = the last 2 hours of observed radar.
    for (var minAgo = 120; minAgo >= 0; minAgo -= 10) {
      final t = now.subtract(Duration(minutes: minAgo));
      final iso = '${t.toIso8601String().split('.').first}Z';
      frames.add(_RadarFrame(t.millisecondsSinceEpoch ~/ 1000, iso, false));
    }

    // Visible area + 25% margin gives headroom for small pans without a reload.
    final b = _mapController.camera.visibleBounds;
    final latSpan = b.north - b.south;
    final lonSpan = b.east - b.west;
    const margin = 0.25;
    final south = b.south - latSpan * margin;
    final north = b.north + latSpan * margin;
    final west = b.west - lonSpan * margin;
    final east = b.east + lonSpan * margin;
    final bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));

    final (minx, miny) = _toMercator(south, west);
    final (maxx, maxy) = _toMercator(north, east);
    const w = 1024;
    final h = (((maxy - miny) / (maxx - minx)) * w).round().clamp(256, 1024);

    String urlFor(_RadarFrame f) =>
        'https://opengeo.ncep.noaa.gov/geoserver/conus/wms'
        '?service=WMS&version=1.3.0&request=GetMap'
        '&layers=conus_cref_qcd&crs=EPSG:3857'
        '&bbox=$minx,$miny,$maxx,$maxy'
        '&width=$w&height=$h'
        '&format=image/png&transparent=true'
        '&time=${Uri.encodeComponent(f.template)}';

    final urls = [for (final f in frames) urlFor(f)];

    if (!mounted) return;
    setState(() {
      _radarFrames = frames;
      _radarImageUrls = urls;
      _radarBounds = bounds;
      _radarPastCount = frames.length; // all observed; "now" = last frame
      _radarIndex = frames.length - 1; // show the latest frame immediately
      // Forecast frames are bounds-dependent too — rebuild them for this view.
      _forecastGrids = []; _forecastImages = []; _forecastTimes = [];
      _loading = false;
    });
    // Pre-cache every frame BEFORE starting the loop so playback is smooth from
    // the first pass (the latest frame above already shows live radar). Capped
    // so a slow frame can't stall the animation indefinitely.
    await _precacheRadar();
    if (!mounted) return;
    if (_radarPlaying) _startAnim();
    // Auto-load the model forecast overlay to extend the timeline past now.
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) _fetchForecast();
    });
  }

  Future<void> _precacheRadar() async {
    if (!mounted) return;
    await Future.wait([
      for (final url in _radarImageUrls)
        precacheImage(NetworkImage(url), context).catchError((_) {}),
    ]).timeout(const Duration(seconds: 6), onTimeout: () => <void>[]);
  }

  // Animated GOES-East clean-IR from NASA GIBS: 10-min frames over ~2h. GIBS
  // runs ~25-30 min behind real time, so we floor to the 10-min grid and start
  // ~30 min back to ensure every frame exists. Reuses the radar timeline.
  //
  // Like the radar, each frame is fetched as one composited GIBS WMS image
  // over the visible area (+ margin) and pre-cached, so playback swaps
  // pre-decoded images instead of re-tiling GIBS every frame (which made the
  // cloud loop stutter). The image is an opaque IR greyscale (dark = warm/
  // clear, white = cold/cloud), screen-blended over the dark basemap so clear
  // sky reads through and cloud/storm tops glow.
  Future<void> _fetchSatellite() async {
    final now = DateTime.now().toUtc();
    var latest = DateTime.utc(
        now.year, now.month, now.day, now.hour, (now.minute ~/ 10) * 10);
    latest = latest.subtract(const Duration(minutes: 30));
    final frames = <_RadarFrame>[];
    for (var i = 11; i >= 0; i--) {
      final t = latest.subtract(Duration(minutes: 10 * i));
      final iso = '${t.toIso8601String().split('.').first}Z';
      frames.add(_RadarFrame(t.millisecondsSinceEpoch ~/ 1000, iso, false));
    }

    final b = _mapController.camera.visibleBounds;
    final latSpan = b.north - b.south;
    final lonSpan = b.east - b.west;
    const margin = 0.25;
    final south = b.south - latSpan * margin;
    final north = b.north + latSpan * margin;
    final west = b.west - lonSpan * margin;
    final east = b.east + lonSpan * margin;
    final bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));

    final (minx, miny) = _toMercator(south, west);
    final (maxx, maxy) = _toMercator(north, east);
    const w = 1024;
    final h = (((maxy - miny) / (maxx - minx)) * w).round().clamp(256, 1024);

    String urlFor(_RadarFrame f) =>
        'https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi'
        '?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap'
        '&LAYERS=GOES-East_ABI_Band13_Clean_Infrared&CRS=EPSG:3857'
        '&BBOX=$minx,$miny,$maxx,$maxy'
        '&WIDTH=$w&HEIGHT=$h'
        '&FORMAT=image/png&TRANSPARENT=true'
        '&TIME=${Uri.encodeComponent(f.template)}';

    final urls = [for (final f in frames) urlFor(f)];

    if (!mounted) return;
    setState(() {
      _radarFrames = frames;
      _radarImageUrls = urls;
      _radarBounds = bounds;
      _radarPastCount = frames.length; // all observed; "NOW" = latest frame
      _radarIndex = frames.length - 1;
      _loading = false;
    });
    await _precacheRadar();
    if (!mounted) return;
    if (_radarPlaying) _startAnim();
  }

  // Unified animation over all frames: radar tiles first, then forecast overlays.
  void _startAnim() {
    _radarAnim?.cancel();
    if (_totalFrames < 2) return;
    void schedule() {
      final atEnd = _radarIndex >= _totalFrames - 1;
      final onForecast = !_isRadarFrame(_radarIndex);
      final ms = atEnd ? 2000 : onForecast ? 700 : 500;
      _radarAnim = Timer(Duration(milliseconds: ms), () {
        if (!mounted || !_radarPlaying) return;
        final next = atEnd ? 0 : _radarIndex + 1;
        setState(() {
          _radarIndex = next;
          if (!_isRadarFrame(next) && _forecastGrids.isNotEmpty) {
            final fi = _forecastFrameIdx(next);
            _field = _forecastGrids[fi];
            _gradientImage = _forecastImages[fi];
          } else {
            _field = null;
            _gradientImage = null;
          }
        });
        schedule();
      });
    }
    schedule();
  }

  void _jumpToNow() {
    _radarAnim?.cancel();
    // Jump to the latest observed radar frame (end of past, before nowcast).
    final nowIdx = math.max(0, _radarPastCount - 1);
    setState(() {
      _radarIndex = nowIdx;
      _field = null;
      _gradientImage = null;
      _radarPlaying = true;
    });
    _startAnim();
  }

  // NOAA WaveWatch III significant wave height (Thgt, metres) from the PacIOOS
  // ERDDAP mirror — a 0.5° global wave model with a 5-day hourly forecast. One
  // griddap JSON request pulls the next ~48 h (3-hourly, via the time stride)
  // over the view bbox; each time step is resampled onto a finer grid and
  // pre-rendered, then animated — a smooth, NOAA-sourced offshore sea-height
  // loop like StormSurf's Gulf map. ERDDAP longitude is 0–360.
  Future<void> _fetchSeas({bool silent = false}) async {
    _seasAnim?.cancel();
    final cam = _mapController.camera;
    final b = cam.visibleBounds;
    final span = math.max(b.north - b.south, b.east - b.west) * _kGridMargin;
    final step = span / (_seasN - 1);
    final latMin = cam.center.latitude - span / 2;
    final lonMin = cam.center.longitude - span / 2; // −180..180 (map coords)
    final latMax = latMin + span;
    final lonMax = lonMin + span;
    // ERDDAP longitude is 0–360. `shift` maps a 0–360 longitude into a frame
    // anchored at lonLo, so a view crossing the 0/360 seam (antimeridian) stays
    // contiguous; for the common case it's the identity.
    double to360(double d) => d < 0 ? d + 360 : d;
    final lonLo = to360(lonMin), lonHi = to360(lonMax);
    final crosses = lonHi < lonLo;
    double shift(double l) => l < lonLo - 1e-6 ? l + 360 : l;

    final nowUtc = DateTime.now().toUtc();
    final startHr =
        DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, nowUtc.hour);
    final endHr = startHr.add(const Duration(hours: 48));
    String iso(DateTime t) => '${t.toIso8601String().split('.').first}Z';

    // [time (every 3rd index = 3-hourly)][depth (all)][lat range][lon range].
    // A seam-crossing view needs two requests (lonLo→359.5 and 0→lonHi).
    String urlFor(double lo, double hi) {
      final q = 'Thgt%5B(${iso(startHr)}):3:(${iso(endHr)})%5D%5B%5D'
          '%5B(${latMin.toStringAsFixed(3)}):(${latMax.toStringAsFixed(3)})%5D'
          '%5B(${lo.toStringAsFixed(3)}):(${hi.toStringAsFixed(3)})%5D';
      return 'https://pae-paha.pacioos.hawaii.edu/erddap/griddap/ww3_global.json?$q';
    }
    final urls = crosses
        ? [urlFor(lonLo, 359.5), urlFor(0.0, lonHi)]
        : [urlFor(lonLo, lonHi)];

    try {
      final rows = <dynamic>[];
      for (final url in urls) {
        final resp = await _dio.get(url);
        final body = resp.data is String
            ? jsonDecode(resp.data as String)
            : resp.data;
        rows.addAll(((body as Map)['table'] as Map)['rows'] as List);
      }

      // Group values by time; collect the native lat/lon axes (lon shifted
      // into the contiguous frame).
      final order = <String>[];
      final byTime = <String, List<(double, double, double)>>{};
      final latSet = <double>{}, lonSet = <double>{};
      for (final r in rows) {
        final t = r[0] as String;
        final lat = (r[2] as num).toDouble();
        final lon = shift((r[3] as num).toDouble());
        final raw = r[4];
        final val = raw == null ? double.nan : (raw as num).toDouble();
        if (!byTime.containsKey(t)) { byTime[t] = []; order.add(t); }
        byTime[t]!.add((lat, lon, val));
        latSet.add(lat); lonSet.add(lon);
      }
      final nLat = latSet.length, nLon = lonSet.length;
      if (nLat < 2 || nLon < 2 || order.isEmpty) {
        throw Exception('no offshore wave data in view');
      }
      final lat0 = latSet.reduce(math.min), lon0 = lonSet.reduce(math.min);
      const native = 0.5;

      final frames = <({DateTime time, _DataGrid grid, ui.Image image})>[];
      for (final t in order) {
        // Native 2-D grid for this time step (NaN = land / no data).
        final g = List.generate(
            nLat, (_) => List<double>.filled(nLon, double.nan),
            growable: false);
        for (final (lat, lon, val) in byTime[t]!) {
          final i = ((lat - lat0) / native).round();
          final j = ((lon - lon0) / native).round();
          if (i >= 0 && i < nLat && j >= 0 && j < nLon) g[i][j] = val;
        }
        // Resample onto our finer square grid (map coords for render/probe),
        // carrying the per-point water coverage as a soft land mask.
        final pts = <_DataPoint>[];
        for (var ii = 0; ii < _seasN; ii++) {
          final lat = latMin + ii * step;
          for (var jj = 0; jj < _seasN; jj++) {
            final lon = lonMin + jj * step;
            final (v, cov) = _sampleNative(
                g, nLat, nLon, lat0, lon0, native, lat, shift(to360(lon)));
            pts.add(_DataPoint(v, null, cov));
          }
        }
        final grid = _DataGrid(pts, latMin, lonMin, step, _seasN);
        frames.add((
          time: DateTime.parse(t),
          grid: grid,
          image: await _buildGradientImage(grid, _seasColor,
              imgN: 192, masked: true),
        ));
      }

      if (!mounted) return;
      setState(() {
        _seasFrames = frames;
        _seasIndex = 0;
        _field = frames.first.grid;
        _gradientImage = frames.first.image;
        _loading = false;
        _error = null;
        _staleDataTime = null;
      });
      if (_seasPlaying) _startSeasAnim();
    } catch (e) {
      if (!mounted || silent) return; // a failed pan-refetch keeps the old loop
      if (_seasFrames.isEmpty) {
        setState(() {
          _error = 'No NOAA wave model data for this area';
          _loading = false;
        });
      }
    }
  }

  void _startSeasAnim() {
    _seasAnim?.cancel();
    if (_seasFrames.length < 2) return;
    void schedule() {
      final atEnd = _seasIndex >= _seasFrames.length - 1;
      _seasAnim = Timer(Duration(milliseconds: atEnd ? 1800 : 650), () {
        if (!mounted || !_seasPlaying) return;
        final next = atEnd ? 0 : _seasIndex + 1;
        setState(() {
          _seasIndex = next;
          _field = _seasFrames[next].grid;
          _gradientImage = _seasFrames[next].image;
        });
        schedule();
      });
    }
    schedule();
  }

  Future<void> _fetchForecast() async {
    if (_forecastGrids.isNotEmpty) return; // already loaded

    // Denser grid than the live data layers (16x16 = 256 pts) so the forecast
    // overlay reads as smooth detailed precipitation, not blocky patches.
    const fcstN = 16;
    final cam = _mapController.camera;
    final b = cam.visibleBounds;
    final span = math.max(b.north - b.south, b.east - b.west) * 1.3;
    final step = span / (fcstN - 1);
    final latMin = cam.center.latitude - span / 2;
    final lonMin = cam.center.longitude - span / 2;

    final lats = <String>[], lons = <String>[];
    for (var i = 0; i < fcstN; i++) {
      for (var j = 0; j < fcstN; j++) {
        lats.add((latMin + i * step).toStringAsFixed(4));
        lons.add((lonMin + j * step).toStringAsFixed(4));
      }
    }

    try {
      final resp = await _dio.get('https://api.open-meteo.com/v1/forecast',
          queryParameters: {
            'latitude': lats.join(','),
            'longitude': lons.join(','),
            'hourly': 'precipitation',
            'forecast_days': '2',
            'timezone': 'auto',
          });

      final items = resp.data as List;
      if (items.isEmpty || items[0]['hourly'] == null) throw Exception('no data');

      final rawTimes = (items[0]['hourly']['time'] as List)
          .map((t) => DateTime.parse(t as String))
          .toList();

      // Start at the current hour (allow 30 min buffer so we don't skip it).
      final now = DateTime.now();
      var start = rawTimes.indexWhere(
          (t) => t.isAfter(now.subtract(const Duration(minutes: 30))));
      if (start < 0) start = 0;
      final end = math.min(start + 18, rawTimes.length);

      final grids = <_DataGrid>[];
      final images = <ui.Image?>[];
      final times = <DateTime>[];

      for (var h = start; h < end; h++) {
        final pts = items.map<_DataPoint>((item) {
          final list = item['hourly']['precipitation'] as List;
          final v = (list[h] as num?)?.toDouble() ?? 0.0;
          return _DataPoint(v);
        }).toList();
        final grid = _DataGrid(pts, latMin, lonMin, step, fcstN);
        grids.add(grid);
        images.add(await _buildGradientImage(grid, _rainColor));
        times.add(rawTimes[h]);
      }

      if (!mounted) return;
      final wasPlaying = _radarPlaying;
      _radarAnim?.cancel();
      setState(() {
        _forecastGrids = grids;
        _forecastImages = images;
        _forecastTimes = times;
        // Don't reset _radarIndex — keep current playback position.
      });
      if (wasPlaying) _startAnim();
      _fetchHourlyStrip();
    } catch (_) { /* forecast unavailable — radar-only is fine */ }
  }

  String _fmtStale(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  String _fmtClock(int epoch) {
    final t = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String _fmtClock2(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String _fmtHour(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h${t.hour < 12 ? 'a' : 'p'}';
  }

  String _wmoEmoji(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '🌫️';
    if (code <= 55) return '🌦️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '🌨️';
    if (code <= 82) return '🌦️';
    if (code <= 86) return '🌨️';
    return '⛈️';
  }

  Future<void> _fetchHourlyStrip() async {
    try {
      final resp = await _dio.get('https://api.open-meteo.com/v1/forecast',
          queryParameters: {
            'latitude': widget.lat.toStringAsFixed(4),
            'longitude': widget.lon.toStringAsFixed(4),
            'hourly': 'precipitation_probability,temperature_2m,weather_code',
            'forecast_days': '2',
            'timezone': 'auto',
          });
      final data = resp.data as Map;
      final hourly = data['hourly'] as Map;
      final times = (hourly['time'] as List)
          .map((t) => DateTime.parse(t as String))
          .toList();
      final pcts = hourly['precipitation_probability'] as List;
      final temps = hourly['temperature_2m'] as List;
      final codes = hourly['weather_code'] as List;

      final now = DateTime.now();
      var start = times.indexWhere(
          (t) => t.isAfter(now.subtract(const Duration(minutes: 30))));
      if (start < 0) start = 0;
      final end = math.min(start + 18, times.length);

      final strip = <_HourForecast>[];
      for (var i = start; i < end; i++) {
        strip.add(_HourForecast(
          time: times[i],
          tempC: (temps[i] as num? ?? 20).toDouble(),
          precipPct: (pcts[i] as num? ?? 0).toInt(),
          weatherCode: (codes[i] as num? ?? 0).toInt(),
        ));
      }
      if (mounted) setState(() => _hourlyStrip = strip);
    } catch (_) {}
  }


  void _showLayerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LayerPicker(
        current: _currentLayer,
        onSelect: (l) {
          Navigator.pop(context);
          if (l != _currentLayer) _fetchGrid(layer: l);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final def = _kLayers[_currentLayer]!;
    final metric = ref.watch(unitsProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.stationName.toUpperCase()} — ${def.label.toUpperCase()}',
          style: const TextStyle(color: kCyan, fontSize: 13),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers, color: kCyan),
            tooltip: 'Change layer',
            onPressed: _showLayerPicker,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: kCyan),
            tooltip: 'Refresh',
            onPressed: () => _fetchGrid(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.lat, widget.lon),
              initialZoom: 8.0,
              // Keep zoom in a useful band: out past ~4 the 9×9 grid is
              // meaningless; in past ~11 the basemap/grid stops adding detail.
              minZoom: 4,
              maxZoom: 11,
              // Tighten the feel: rotation off (disorienting on a data map),
              // keep drag + fling momentum + pinch/double-tap zoom.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation |
                    InteractiveFlag.pinchMove |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              // Satellite uses a DARK basemap so bright IR cloud/storm tops pop
              // (like a real satellite view); other layers use the light map.
              TileLayer(
                key: ValueKey(def.isSatellite ? 'dark' : 'light'),
                urlTemplate: def.isSatellite
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.mattbettinger.tides',
                retinaMode: true,
                // Prefetch a ring of tiles beyond the view edge so pans reveal
                // loaded map instead of grey squares.
                panBuffer: 2,
              ),
              // NOAA radar layer — only when the current frame is observed radar.
              // WMS layer; the time dimension is swapped per frame (ValueKey
              // forces a reload), and GeoServer snaps to the nearest real frame.
              // Radar: pre-cached composited GetMap image for the current frame
              // (only when the current frame is observed radar, not forecast).
              // Swapping decoded images = smooth playback.
              if (def.isRadar && _radarImageUrls.isNotEmpty &&
                  _radarBounds != null && _isRadarFrame(_radarIndex))
                OverlayImageLayer(
                  overlayImages: [
                    OverlayImage(
                      bounds: _radarBounds!,
                      imageProvider: NetworkImage(_radarImageUrls[_radarIndex]),
                      opacity: 0.78,
                    ),
                  ],
                ),
              // Clouds: animated GOES-East clean-IR satellite from NASA GIBS
              // (free, no key, 10-min frames). Each frame is a pre-cached
              // composited GIBS WMS image (smooth playback, like the radar),
              // screen-blended over the dark basemap so clear sky reads through
              // and cloud/storm tops glow.
              if (def.isSatellite && _radarImageUrls.isNotEmpty &&
                  _radarBounds != null && _isRadarFrame(_radarIndex))
                _BlendMask(
                  blendMode: BlendMode.screen,
                  child: OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: _radarBounds!,
                        imageProvider: NetworkImage(_radarImageUrls[_radarIndex]),
                      ),
                    ],
                  ),
                ),
              // Coastline + place labels drawn ON TOP of the satellite so the
              // coast and bays stay visible for orientation — e.g. to see
              // whether a cell will hit your bay/beach. The Esri Ocean
              // reference (transparent, free) is a faint grey, so we recolour
              // it to bright cyan (srcIn keeps the line shapes, swaps the
              // colour) to make it pop against the dark map and the clouds.
              if (def.isSatellite)
                ColorFiltered(
                  colorFilter:
                      const ColorFilter.mode(kCyan, BlendMode.srcIn),
                  child: TileLayer(
                    urlTemplate:
                        'https://services.arcgisonline.com/ArcGIS/rest/services/'
                        'Ocean/World_Ocean_Reference/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.mattbettinger.tides',
                  ),
                ),
              if (_field != null && _gradientImage != null)
                _SmoothGradientLayer(field: _field!, image: _gradientImage!),
              if (_field != null && def.hasIsobars)
                _IsobarLayer(field: _field!),
              if (_field != null && def.hasFlow)
                _WindParticleLayer(
                    field: _field,
                    colorFn: def.colorFn,
                    skipEmpty: def.isMarine),
              // Station pin removed: the centre crosshair now marks the read
              // point, so a separate (and geographically-anchored) pin only
              // added clutter and drifted off-centre while panning.
              RichAttributionWidget(
                attributions: [
                  const TextSourceAttribution('© CARTO'),
                  const TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution(def.isRadar
                      ? (_isRadarFrame(_radarIndex) ? 'NOAA / NWS' : 'Open-Meteo')
                      : def.isSatellite
                          ? 'NASA GIBS · NOAA GOES · Esri'
                          : def.isSeas
                              ? 'NOAA NWS WaveWatch III · PacIOOS ERDDAP'
                              : 'Open-Meteo'),
                ],
              ),
            ],
          ),
          // Stale-data banner: Open-Meteo was unreachable; showing last cached grid.
          // The refresh icon in the app bar retries — tap it when service recovers.
          if (_staleDataTime != null && !_loading)
            Positioned(
              top: 10, left: 12, right: 12,
              child: Center(
                child: GestureDetector(
                  onTap: () => _fetchGrid(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade800.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 13),
                        const SizedBox(width: 6),
                        Text(
                          'Open-Meteo down · last data ${_fmtStale(_staleDataTime!)} · tap to retry',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: kCyan),
                    const SizedBox(height: 12),
                    Text('Loading ${def.label.toLowerCase()}…',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, color: Colors.white38, size: 40),
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _fetchGrid(),
                    child: const Text('Retry',
                        style: TextStyle(color: kCyan)),
                  ),
                ],
              ),
            ),
          // Hide legend when the hourly strip is showing (strip gives more context).
          if (!_loading && _error == null &&
              !(def.isRadar && _hourlyStrip.isNotEmpty))
            _legend(def, metric),
          if ((def.isRadar || def.isSatellite) && _radarFrames.isNotEmpty && !_loading && _error == null)
            _radarTimeline(),
          if (def.isSeas && _seasFrames.isNotEmpty && !_loading && _error == null)
            _seasTimeline(),
          if (def.isRadar && _hourlyStrip.isNotEmpty && !_loading && _error == null)
            _hourlyStripWidget(metric),
          // Fixed centre reticle — the readout always reflects this crosshair.
          if (_field != null && !_loading && _error == null &&
              !def.isRadar && !def.isSatellite)
            const IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CustomPaint(painter: _CrosshairPainter()),
                ),
              ),
            ),
          if (_field != null && !_loading && _error == null)
            _probeReadout(def, metric),
          MapRecenterButton(
            visible: _showRecenter,
            bottom: 120,
            onPressed: () {
              _mapController.move(
                  LatLng(widget.lat, widget.lon), _initialZoom(_currentLayer));
              setState(() => _showRecenter = false);
            },
          ),
        ],
      ),
    );
  }

  // ── Unified radar + forecast timeline ────────────────────────────────────

  Widget _radarTimeline() {
    final total = _totalFrames;
    final idx = _radarIndex.clamp(0, math.max(0, total - 1)).toInt();
    final onRadar = _isRadarFrame(idx);

    // Time label: past = white, nowcast = amber ▸, forecast = amber +Xh
    String timeLabel;
    bool isFuture;
    if (onRadar && _radarFrames.isNotEmpty) {
      final f = _radarFrames[idx];
      isFuture = _isNowcastFrame(idx);
      timeLabel = isFuture ? '${_fmtClock(f.time)} ▸' : _fmtClock(f.time);
    } else if (!onRadar && _forecastTimes.isNotEmpty) {
      final fi = _forecastFrameIdx(idx);
      if (fi >= 0 && fi < _forecastTimes.length) {
        final t = _forecastTimes[fi];
        final hoursAhead = t.difference(DateTime.now()).inHours;
        timeLabel = '${_fmtClock2(t)}  +${hoursAhead}h';
      } else {
        timeLabel = '—';
      }
      isFuture = true;
    } else {
      timeLabel = '—';
      isFuture = false;
    }

    // Footer: show full span — radar start to forecast end (or radar end).
    final startStr = _radarFrames.isNotEmpty
        ? _fmtClock(_radarFrames.first.time) : '';
    final endStr = _forecastTimes.isNotEmpty
        ? _fmtClock2(_forecastTimes.last)
        : _radarFrames.isNotEmpty ? _fmtClock(_radarFrames.last.time) : '';
    final radarH = _radarFrames.isNotEmpty
        ? ((_radarFrames.last.time - _radarFrames.first.time) / 3600).round()
        : 0;
    final fcstH = _forecastTimes.length;
    final noun = _kLayers[_currentLayer]!.isSatellite ? 'satellite' : 'radar';
    final midLabel = fcstH > 0
        ? '${radarH}h radar  +  ${fcstH}h forecast'
        : '${radarH}h of $noun';

    return Positioned(
      top: 10,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // ⏺ NOW button — jump to current time
                TextButton(
                  onPressed: _radarFrames.isNotEmpty ? _jumpToNow : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: kCyan,
                  ),
                  child: const Text('NOW',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8)),
                ),
                IconButton(
                  icon: Icon(
                      _radarPlaying ? Icons.pause : Icons.play_arrow,
                      color: kCyan),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () {
                    setState(() => _radarPlaying = !_radarPlaying);
                    if (_radarPlaying) { _startAnim(); }
                    else { _radarAnim?.cancel(); }
                  },
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      min: 0,
                      max: math.max(1, total - 1).toDouble(),
                      divisions: math.max(1, total - 1),
                      value: idx.toDouble(),
                      activeColor: kCyan,
                      inactiveColor: Colors.white24,
                      onChanged: total < 2
                          ? null
                          : (v) {
                              _radarAnim?.cancel();
                              final newIdx = v.round();
                              setState(() {
                                _radarPlaying = false;
                                _radarIndex = newIdx;
                                if (!_isRadarFrame(newIdx) &&
                                    _forecastGrids.isNotEmpty) {
                                  final fi = _forecastFrameIdx(newIdx);
                                  _field = _forecastGrids[fi];
                                  _gradientImage = _forecastImages[fi];
                                } else {
                                  _field = null;
                                  _gradientImage = null;
                                }
                              });
                            },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: Text(
                    timeLabel,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: isFuture ? Colors.amber : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            // Full time-span footer: radar start → forecast end
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(startStr,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 9)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(midLabel,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 9)),
                      if (_forecastGrids.isEmpty && _radarFrames.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        const SizedBox(
                          width: 9, height: 9,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.2, color: Colors.white24),
                        ),
                      ],
                    ],
                  ),
                  Text(endStr,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Touch-to-read value ───────────────────────────────────────────────────

  // ── Seas (WW3) forecast timeline ─────────────────────────────────────────
  Widget _seasTimeline() {
    final total = _seasFrames.length;
    final idx = _seasIndex.clamp(0, math.max(0, total - 1)).toInt();
    final t = _seasFrames[idx].time;
    final hoursAhead = t.difference(DateTime.now().toUtc()).inHours;
    final label = hoursAhead <= 0
        ? 'now'
        : '${_fmtClock2(t.toLocal())}  +${hoursAhead}h';
    final spanH = total > 1
        ? _seasFrames.last.time.difference(_seasFrames.first.time).inHours
        : 0;

    return Positioned(
      top: 10,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_seasPlaying ? Icons.pause : Icons.play_arrow,
                      color: kCyan),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () {
                    setState(() => _seasPlaying = !_seasPlaying);
                    if (_seasPlaying) {
                      _startSeasAnim();
                    } else {
                      _seasAnim?.cancel();
                    }
                  },
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      min: 0,
                      max: math.max(1, total - 1).toDouble(),
                      divisions: math.max(1, total - 1),
                      value: idx.toDouble(),
                      activeColor: kCyan,
                      inactiveColor: Colors.white24,
                      onChanged: total < 2
                          ? null
                          : (v) {
                              _seasAnim?.cancel();
                              final ni = v.round();
                              setState(() {
                                _seasPlaying = false;
                                _seasIndex = ni;
                                _field = _seasFrames[ni].grid;
                                _gradientImage = _seasFrames[ni].image;
                              });
                            },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 86,
                  child: Text(
                    label,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: hoursAhead <= 0 ? Colors.white : Colors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('NOAA WaveWatch III  ·  ${spanH}h forecast',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _probeReadout(_LayerDef def, bool metric) {
    final sample = _field!.pointAt(_readPoint.latitude, _readPoint.longitude);
    final text = _readoutText(def, sample, metric);
    return Positioned(
      // Drop below the Seas forecast timeline, which occupies the top strip.
      top: def.isSeas ? 72 : 12,
      left: 12,
      right: 12,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kCyan.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(def.icon, color: kCyan, size: 15),
              const SizedBox(width: 7),
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  String _readoutText(_LayerDef def, _DataPoint? sample, bool metric) {
    if (sample == null) return 'Outside data area';
    final v = sample.value;
    final dirStr =
        sample.direction != null ? ' ${_compass(sample.direction!)}' : '';
    switch (_currentLayer) {
      case _Layer.wind:
        final s = metric ? v * 1.60934 : v;
        return '${s.toStringAsFixed(0)} ${metric ? 'km/h' : 'mph'}$dirStr';
      case _Layer.waves:
      case _Layer.swell:
      case _Layer.seas:
        final cov =
            _field!.coverageAt(_readPoint.latitude, _readPoint.longitude);
        if (cov < 0.4) return 'Land — no wave data';
        // Open-Meteo marine grids store 0 at land points; un-dilute the
        // near-coast bilinear the same way the wash render does.
        final mtrs = _currentLayer == _Layer.seas ? v : v / cov;
        if (mtrs < 0.05) return 'No waves here';
        final h = metric ? mtrs : mtrs * 3.28084; // grid values are metres
        return '${h.toStringAsFixed(1)} ${metric ? 'm' : 'ft'}$dirStr';
      case _Layer.rain:
        return v < 0.05 ? 'No rain' : '${v.toStringAsFixed(1)} mm';
      case _Layer.temp:
        final t = metric ? v : v * 9 / 5 + 32;
        return '${t.toStringAsFixed(0)}°${metric ? 'C' : 'F'}';
      case _Layer.pressure:
        return '${v.toStringAsFixed(0)} hPa';
      case _Layer.clouds:
        return '${v.toStringAsFixed(0)}% cloud';
    }
  }

  static const _compassPts = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  String _compass(double deg) =>
      _compassPts[((deg % 360) / 22.5).round() % 16];

  // ── Hourly forecast strip (FCST mode, Rain layer) ────────────────────────────

  Widget _hourlyStripWidget(bool metric) {
    if (_hourlyStrip.isEmpty) return const SizedBox.shrink();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.94),
              Colors.black.withValues(alpha: 0.72),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: kCyan, size: 11),
                    SizedBox(width: 5),
                    Text('HOURLY FORECAST',
                        style: TextStyle(
                            color: kCyan, fontSize: 11, letterSpacing: 1.2)),
                    Spacer(),
                    Text('Open-Meteo',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 9)),
                  ],
                ),
              ),
              SizedBox(
                height: 84,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: _hourlyStrip.length,
                  itemBuilder: (ctx, i) =>
                      _hourColumn(_hourlyStrip[i], i == 0, metric),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hourColumn(_HourForecast h, bool isNow, bool metric) {
    final label = isNow ? 'NOW' : _fmtHour(h.time);
    final temp = metric ? h.tempC : h.tempC * 9 / 5 + 32;
    final pct = h.precipPct;
    final pctColor = pct >= 60
        ? const Color(0xFF4BCFFA)
        : pct >= 30
            ? Colors.amber
            : Colors.white38;
    return Container(
      width: 56,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: isNow
          ? BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: kCyan.withValues(alpha: 0.6), width: 2)),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(label,
              style: TextStyle(
                color: isNow ? kCyan : Colors.white54,
                fontSize: 11,
                fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
              )),
          Text(_wmoEmoji(h.weatherCode),
              style: const TextStyle(fontSize: 18)),
          Text('${temp.round()}°',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text('$pct%',
              style: TextStyle(color: pctColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _legend(_LayerDef def, bool metric) => Positioned(
        // Lift above the system navigation/gesture bar (e.g. Samsung) so the
        // legend isn't clipped by it.
        bottom: 32 + MediaQuery.of(context).viewPadding.bottom,
        left: 12,
        right: 12,
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Layer name so people know what they're looking at
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(def.icon, color: kCyan, size: 13),
                    const SizedBox(width: 5),
                    Text(
                      def.label.toUpperCase(),
                      style: const TextStyle(
                        color: kCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: def.legendFor(metric).expand((item) => [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: item.$1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(item.$2,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ),
                  ]).toList(),
                ),
              ],
            ),
          ),
        ),
      );
}

// Fixed centre crosshair drawn over the map. White lines over a dark halo so it
// reads on both the light and (satellite) dark basemaps; a small cyan dot marks
// the exact sample point that drives the readout panel.
class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const gap = 5.0; // clear window around the centre dot
    const arm = 13.0; // length of each crosshair arm from centre

    void drawArms(Color color, double width) {
      final p = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(c.dx - arm, c.dy), Offset(c.dx - gap, c.dy), p);
      canvas.drawLine(Offset(c.dx + gap, c.dy), Offset(c.dx + arm, c.dy), p);
      canvas.drawLine(Offset(c.dx, c.dy - arm), Offset(c.dx, c.dy - gap), p);
      canvas.drawLine(Offset(c.dx, c.dy + gap), Offset(c.dx, c.dy + arm), p);
    }

    drawArms(Colors.black54, 4); // halo for contrast
    drawArms(Colors.white, 2); // bright crosshair
    canvas.drawCircle(c, 2.5, Paint()..color = kCyan);
    canvas.drawCircle(
        c,
        2.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}
