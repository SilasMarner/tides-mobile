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
  return c.withOpacity(0.45);
}

Color _waveColor(double m) {
  if (m < 0.1) return Colors.transparent;
  final c = m < 0.5 ? const Color(0xFF7FB3D3)
          : m < 1.0 ? const Color(0xFF2980B9)
          : m < 2.0 ? const Color(0xFF1A5276)
          : m < 4.0 ? const Color(0xFF0D2137)
          :             const Color(0xFF07111E);
  return c.withOpacity(0.50);
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
  return c.withOpacity(0.55);
}

Color _rainColor(double mm) {
  if (mm < 0.1) return Colors.transparent;
  final c = mm < 1.0 ? const Color(0xFFAED6F1)
          : mm < 2.0 ? const Color(0xFF5DADE2)
          : mm < 5.0 ? const Color(0xFF2E86C1)
          : mm < 10  ? const Color(0xFF1A5276)
          :              const Color(0xFF4A235A);
  return c.withOpacity(0.55);
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
  return c.withOpacity(0.50);
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
  return c.withOpacity(0.28);
}

Color _cloudColor(double pct) {
  final t = (pct / 100.0).clamp(0.0, 1.0);
  return Colors.white.withOpacity(t * 0.48);
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
    label: 'Rain', icon: Icons.umbrella,
    isMarine: false, hasFlow: false,
    valueVar: 'precipitation', colorFn: _rainColor,
    legend: [
      (Color(0xFFAED6F1), '<1mm'),
      (Color(0xFF5DADE2), '1–2mm'),
      (Color(0xFF2E86C1), '2–5mm'),
      (Color(0xFF4A235A), '>5mm'),
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
      {super.key, required this.field, required this.image});

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
  const _IsobarLayer({super.key, required this.field});

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

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withOpacity(0.45);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    final rect = Offset.zero & size;
    final placedLabels = <Offset>[];

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
            canvas.drawLine(crossings[0], crossings[1], glow);
            canvas.drawLine(crossings[0], crossings[1], line);
            if (crossings.length == 4) {
              canvas.drawLine(crossings[2], crossings[3], glow);
              canvas.drawLine(crossings[2], crossings[3], line);
            }

            // Label this level once, spaced out from other labels.
            if (!labelPlacedForLevel) {
              final mid = Offset((crossings[0].dx + crossings[1].dx) / 2,
                  (crossings[0].dy + crossings[1].dy) / 2);
              if (rect.contains(mid) &&
                  placedLabels.every((p) => (p - mid).distance > 70)) {
                _label(canvas, mid, level.toStringAsFixed(labelDecimals));
                placedLabels.add(mid);
                labelPlacedForLevel = true;
              }
            }
          }
        }
      }
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
        center: at, width: tp.width + 8, height: tp.height + 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(7)),
      Paint()..color = Colors.black.withOpacity(0.65),
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
      {super.key,
      required this.field,
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
      // otherwise base.withOpacity() below would paint a black dot.
      if (base.alpha == 0) continue;

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
            ..color = base.withOpacity((frac * p.opacity * 0.95).clamp(0, 1))
            ..strokeWidth = 0.5 + frac * 1.8,
        );
      }

      if (allPts.isNotEmpty) {
        canvas.drawCircle(allPts.last, 2.0,
            Paint()..color = base.withOpacity(p.opacity));
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
    super.dispose();
  }

  // Re-fetch (quietly) when the user pans/zooms so the overlay always covers
  // the visible area — like Windy, the data follows the map.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _fetchGrid(silent: true);
    });
  }

  Future<void> _fetchGrid({_Layer? layer, bool silent = false}) async {
    final def = _kLayers[layer ?? _currentLayer]!;
    if (!silent) {
      setState(() {
        _loading = true; _error = null;
        _field = null; _gradientImage = null; _probe = null;
      });
    }
    if (layer != null) {
      setState(() => _currentLayer = layer);
      // Pressure is a synoptic-scale field — zoom out so isobars are visible,
      // like Windy. Other layers recenter on the station at a local view.
      _mapController.move(
        LatLng(widget.lat, widget.lon),
        layer == _Layer.pressure ? 6.0 : 8.0,
      );
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
        if (mounted && !silent) setState(() {
          _error = def.isMarine
              ? 'No ${def.label.toLowerCase()} data at this location'
              : 'No data available';
          _loading = false;
        });
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

  Future<ui.Image> _buildGradientImage(
      _DataGrid field, Color Function(double) colorFn) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final n = field.n;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        // row 0 = north (latMax), row n-1 = south (latMin)
        final lat = field.latMin + (n - 1 - row) * field.step;
        final lon = field.lonMin + col * field.step;
        final val = field.primaryAt(lat, lon);
        c.drawRect(
          Rect.fromLTWH(col.toDouble(), row.toDouble(), 1, 1),
          Paint()..color = colorFn(val),
        );
      }
    }
    final pict = recorder.endRecording();
    return pict.toImage(n, n);
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
                        color: kCyan.withOpacity(0.4),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© CARTO'),
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('Open-Meteo'),
                ],
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.55),
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
          if (!_loading && _error == null) _legend(def, metric),
          if (_probe != null && _field != null && !_loading && _error == null)
            _probeReadout(def, metric)
          else if (_probe == null && _field != null && !_loading && _error == null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
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
            color: Colors.black.withOpacity(0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kCyan.withOpacity(0.5)),
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

  Widget _legend(_LayerDef def, bool metric) => Positioned(
        bottom: 32,
        left: 12,
        right: 12,
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
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
