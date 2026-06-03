import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/units_provider.dart';
import '../theme.dart';

// ── Color ramps (opacity baked in) ───────────────────────────────────────────

Color _windColor(double mph) {
  final c = mph < 2  ? const Color(0xFFFFFFFF)
          : mph < 5  ? const Color(0xFF98ECFF)
          : mph < 10 ? const Color(0xFF4BCFFA)
          : mph < 15 ? const Color(0xFF56E39F)
          : mph < 20 ? const Color(0xFFF9CA24)
          : mph < 25 ? const Color(0xFFF0932B)
          : mph < 35 ? const Color(0xFFEB4D4B)
          :             const Color(0xFF6C5CE7);
  return c.withValues(alpha: 0.45);
}

Color _waveColor(double m) {
  if (m < 0.1) return Colors.transparent;
  final c = m < 0.5 ? const Color(0xFF7FB3D3)
          : m < 1.0 ? const Color(0xFF2980B9)
          : m < 2.0 ? const Color(0xFF1A5276)
          : m < 4.0 ? const Color(0xFF0D2137)
          :             const Color(0xFF07111E);
  return c.withValues(alpha: 0.50);
}

Color _swellColor(double m) {
  if (m < 0.1) return Colors.transparent;
  // Cyan → indigo → purple → magenta: distinct hues that read clearly both
  // on the map and as legend dots, and stand apart from the blue wave layer.
  final c = m < 0.5 ? const Color(0xFF4DD0E1)
          : m < 1.0 ? const Color(0xFF5C6BC0)
          : m < 2.0 ? const Color(0xFF7E57C2)
          : m < 4.0 ? const Color(0xFFAB47BC)
          :             const Color(0xFFEC407A);
  return c.withValues(alpha: 0.55);
}

Color _rainColor(double mm) {
  if (mm < 0.1) return Colors.transparent;
  final c = mm < 1.0 ? const Color(0xFFAED6F1)
          : mm < 2.0 ? const Color(0xFF5DADE2)
          : mm < 5.0 ? const Color(0xFF2E86C1)
          : mm < 10  ? const Color(0xFF1A5276)
          :              const Color(0xFF4A235A);
  return c.withValues(alpha: 0.55);
}

Color _tempColor(double degC) {
  final c = degC < -5  ? const Color(0xFF4A235A)
          : degC < 0   ? const Color(0xFF1A5276)
          : degC < 5   ? const Color(0xFF2E86C1)
          : degC < 10  ? const Color(0xFFAED6F1)
          : degC < 15  ? const Color(0xFFA9DFBF)
          : degC < 20  ? const Color(0xFFF9E79F)
          : degC < 25  ? const Color(0xFFF9CA24)
          : degC < 30  ? const Color(0xFFF0932B)
          : degC < 35  ? const Color(0xFFEB4D4B)
          :               const Color(0xFF922B21);
  return c.withValues(alpha: 0.50);
}

Color _pressureColor(double hpa) {
  final c = hpa < 990  ? const Color(0xFF6C5CE7)
          : hpa < 1000 ? const Color(0xFF4BCFFA)
          : hpa < 1008 ? const Color(0xFF56E39F)
          : hpa < 1013 ? const Color(0xFFFFFFFF)
          : hpa < 1018 ? const Color(0xFFF9CA24)
          : hpa < 1023 ? const Color(0xFFF0932B)
          :               const Color(0xFFEB4D4B);
  // Keep the wash subtle — the isobar lines carry the detail.
  return c.withValues(alpha: 0.28);
}

Color _cloudColor(double pct) {
  final t = (pct / 100.0).clamp(0.0, 1.0);
  return Colors.white.withValues(alpha: t * 0.48);
}

// ── Data model ────────────────────────────────────────────────────────────────

class _DataPoint {
  final double value;
  final double? direction;
  const _DataPoint(this.value, [this.direction]);
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

// ── Layer system ───────────────────────────────────────────────────────────────

enum _Layer { wind, waves, swell, rain, temp, pressure, clouds }


class _LayerDef {
  final String label;
  final IconData icon;
  final bool isMarine;
  final bool hasFlow;
  final bool hasIsobars;
  final bool isRadar; // overlay live weather-radar tiles instead of a grid
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
    isMarine: false, hasFlow: false,
    valueVar: 'cloud_cover', colorFn: _cloudColor,
    legend: [
      (Color(0x28FFFFFF), '<25%'),
      (Color(0x55FFFFFF), '25–50%'),
      (Color(0x99FFFFFF), '50–75%'),
      (Color(0xCCFFFFFF), '>75%'),
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
      Rect.fromLTWH(0, 0, field.n.toDouble(), field.n.toDouble()),
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

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ParticlePainter(List.unmodifiable(_particles),
            MapCamera.of(context), widget.field, widget.colorFn),
        child: const SizedBox.expand(),
      );
}

// ── Particle painter ──────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final MapCamera camera;
  final _DataGrid? field;
  final Color Function(double) colorFn;
  _ParticlePainter(this.particles, this.camera, this.field, this.colorFn);

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
  LatLng? _probe; // point the user tapped to read a value
  Timer? _moveDebounce;
  // Radar animation (rain layer): NOAA WMS frames (past) + forecast overlays.
  List<_RadarFrame> _radarFrames = [];
  int _radarIndex = 0;
  bool _radarPlaying = true;
  Timer? _radarAnim;
  // Forecast overlay: Open-Meteo hourly precipitation grids (auto-loaded).
  List<_DataGrid> _forecastGrids = [];
  List<ui.Image?> _forecastImages = [];
  List<DateTime> _forecastTimes = [];
  int _radarPastCount = 0; // how many _radarFrames entries are observed (not nowcast)
  // Hourly strip: single-point forecast for the bottom panel.
  List<_HourForecast> _hourlyStrip = [];

  // ── Unified frame helpers ─────────────────────────────────────────────────
  int get _totalFrames => _radarFrames.length + _forecastGrids.length;
  bool _isRadarFrame(int i) => i < _radarFrames.length;
  bool _isNowcastFrame(int i) =>
      i >= _radarPastCount && i < _radarFrames.length;
  int _forecastFrameIdx(int i) => i - _radarFrames.length;

  static const _n = 9;

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
    super.dispose();
  }

  // Re-fetch (quietly) when the user pans/zooms so the overlay always covers
  // the visible area — like Windy, the data follows the map.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    // Radar is a tile layer — it self-loads on pan/zoom. We deliberately do
    // NOT precache the other frames here: a burst of tile requests would
    // starve the basemap and leave the panned-to area blank.
    if (_kLayers[_currentLayer]!.isRadar) return;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _fetchGrid(silent: true);
    });
  }

  Future<void> _fetchGrid({_Layer? layer, bool silent = false}) async {
    final def = _kLayers[layer ?? _currentLayer]!;
    if (!silent) {
      _radarAnim?.cancel();
      setState(() {
        _loading = true; _error = null;
        _field = null; _gradientImage = null; _probe = null;
        _radarFrames = []; _radarPastCount = 0;
        _forecastGrids = []; _forecastImages = []; _forecastTimes = [];
        _hourlyStrip = [];
      });
    }
    if (layer != null) {
      setState(() => _currentLayer = layer);
      // Pressure is a synoptic-scale field — zoom out so isobars are visible,
      // like Windy. Other layers recenter on the station at a local view.
      _mapController.move(
        LatLng(widget.lat, widget.lon),
        layer == _Layer.pressure ? 6.0 : layer == _Layer.rain ? 7.0 : 8.0,
      );
    }

    // Rain uses live weather-radar tiles rather than a sampled grid.
    if (def.isRadar) {
      await _fetchRadar();
      return;
    }

    // Size a square grid to cover the current view (wider dimension) + margin.
    final cam = _mapController.camera;
    final b = cam.visibleBounds;
    final span = math.max(b.north - b.south, b.east - b.west) * 1.3;
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
        final v = (c[def.valueVar]  as num?)?.toDouble() ?? 0.0;
        final d = def.directionVar != null
            ? (c[def.directionVar!] as num?)?.toDouble()
            : null;
        return _DataPoint(v, d);
      }).toList();

      final field = _DataGrid(pts, latMin, lonMin, step, _n);
      final img = await _buildGradientImage(field, def.colorFn);

      if (mounted) {
        setState(() {
          _field = field;
          _gradientImage = img;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() { _error = 'Could not load data'; _loading = false; });
      }
    }
  }

  // Live precipitation radar from NOAA MRMS composite reflectivity
  // (conus_cref_qcd) via WMS — free, no key, US coverage, ~2 min cadence and
  // full-resolution detail (same mosaic the major weather apps render).
  //
  // GeoServer's time dimension uses nearestValue="1", so we generate
  // approximate timestamps over the past ~2h and the server snaps each request
  // to the closest real frame — no GetCapabilities XML parsing needed. For NOAA
  // frames `_RadarFrame.template` holds the ISO-8601 time string (not a URL).
  Future<void> _fetchRadar() async {
    final now = DateTime.now().toUtc();
    final frames = <_RadarFrame>[];
    // 13 frames at 10-min spacing = the last 2 hours of observed radar.
    for (var minAgo = 120; minAgo >= 0; minAgo -= 10) {
      final t = now.subtract(Duration(minutes: minAgo));
      final iso = '${t.toIso8601String().split('.').first}Z';
      frames.add(_RadarFrame(t.millisecondsSinceEpoch ~/ 1000, iso, false));
    }
    if (!mounted) return;
    setState(() {
      _radarFrames = frames;
      _radarPastCount = frames.length; // all observed; "now" = last frame
      _radarIndex = frames.length - 1;
      _loading = false;
    });
    if (_radarPlaying) _startAnim();
    // Auto-load the model forecast overlay to extend the timeline past now.
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) _fetchForecast();
    });
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


  Future<ui.Image> _buildGradientImage(
      _DataGrid field, Color Function(double) colorFn) async {
    // Render at 128×128 regardless of data grid size. We sample the grid's
    // bilinear interpolation at every pixel so the output is smooth — no
    // blocky stretched tiles even though the underlying data is only 9×9.
    const imgN = 128;
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final latSpan = field.latMax - field.latMin;
    final lonSpan = field.lonMax - field.lonMin;
    for (var row = 0; row < imgN; row++) {
      for (var col = 0; col < imgN; col++) {
        final lat = field.latMax - (row / (imgN - 1)) * latSpan;
        final lon = field.lonMin + (col / (imgN - 1)) * lonSpan;
        final val = field.primaryAt(lat, lon);
        c.drawRect(
          Rect.fromLTWH(col.toDouble(), row.toDouble(), 1, 1),
          Paint()..color = colorFn(val),
        );
      }
    }
    final pict = recorder.endRecording();
    return pict.toImage(imgN, imgN);
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
              onTap: (_, latLng) {
                if (_field != null) setState(() => _probe = latLng);
              },
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.mattbettinger.tides',
                retinaMode: true,
              ),
              // NOAA radar layer — only when the current frame is observed radar.
              // WMS layer; the time dimension is swapped per frame (ValueKey
              // forces a reload), and GeoServer snaps to the nearest real frame.
              if (def.isRadar && _radarFrames.isNotEmpty && _isRadarFrame(_radarIndex))
                Opacity(
                  opacity: 0.78,
                  child: TileLayer(
                    key: ValueKey('radar-${_radarFrames[_radarIndex].template}'),
                    wmsOptions: WMSTileLayerOptions(
                      baseUrl:
                          'https://opengeo.ncep.noaa.gov/geoserver/conus/wms?',
                      layers: const ['conus_cref_qcd'],
                      format: 'image/png',
                      transparent: true,
                      otherParameters: {
                        'time': _radarFrames[_radarIndex].template,
                      },
                    ),
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
              if (_probe != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _probe!,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kCyan.withValues(alpha: 0.4),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ]),
              RichAttributionWidget(
                attributions: [
                  const TextSourceAttribution('© CARTO'),
                  const TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution(def.isRadar
                      ? (_isRadarFrame(_radarIndex) ? 'NOAA / NWS' : 'Open-Meteo')
                      : 'Open-Meteo'),
                ],
              ),
            ],
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
          if (def.isRadar && _radarFrames.isNotEmpty && !_loading && _error == null)
            _radarTimeline(),
          if (def.isRadar && _hourlyStrip.isNotEmpty && !_loading && _error == null)
            _hourlyStripWidget(metric),
          if (_probe != null && _field != null && !_loading && _error == null)
            _probeReadout(def, metric)
          else if (_probe == null && _field != null && !_loading &&
              _error == null && !def.isRadar)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Tap the map to read a value',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ),
              ),
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
    final midLabel = fcstH > 0
        ? '${radarH}h radar  +  ${fcstH}h forecast'
        : '${radarH}h of radar';

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

  Widget _probeReadout(_LayerDef def, bool metric) {
    final sample = _field!.pointAt(_probe!.latitude, _probe!.longitude);
    final text = _readoutText(def, sample, metric);
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
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
              const SizedBox(width: 2),
              InkWell(
                onTap: () => setState(() => _probe = null),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white54, size: 16),
                ),
              ),
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
        if (v < 0.05) return 'No waves here';
        final h = metric ? v : v * 3.28084; // grid values are metres
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
