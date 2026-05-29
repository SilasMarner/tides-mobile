import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';

// ── Windy-style colour ramp ───────────────────────────────────────────────────
Color _speedColor(double mph) {
  if (mph < 2) return const Color(0xFFFFFFFF);
  if (mph < 5) return const Color(0xFF98ECFF);
  if (mph < 10) return const Color(0xFF4BCFFA);
  if (mph < 15) return const Color(0xFF56E39F);
  if (mph < 20) return const Color(0xFFF9CA24);
  if (mph < 25) return const Color(0xFFF0932B);
  if (mph < 35) return const Color(0xFFEB4D4B);
  return const Color(0xFF6C5CE7);
}

// ── Wind grid with bilinear interpolation ────────────────────────────────────
class _WP {
  final double speed, dir;
  const _WP(this.speed, this.dir);
}

class _WindGrid {
  final List<_WP> pts; // row-major [lat_i * n + lon_j]
  final double latMin, lonMin, step;
  final int n;
  const _WindGrid(this.pts, this.latMin, this.lonMin, this.step, this.n);

  /// East (u) and north (v) components in mph, bilinearly interpolated.
  (double, double)? uv(double lat, double lon) {
    final fi = (lat - latMin) / step;
    final fj = (lon - lonMin) / step;
    final i0 = fi.floor(), j0 = fj.floor();
    final i1 = i0 + 1, j1 = j0 + 1;
    if (i0 < 0 || i1 >= n || j0 < 0 || j1 >= n) return null;
    final tx = fi - i0, ty = fj - j0;

    double u(int i, int j) =>
        pts[i * n + j].speed * -math.sin(pts[i * n + j].dir * math.pi / 180);
    double v(int i, int j) =>
        pts[i * n + j].speed * -math.cos(pts[i * n + j].dir * math.pi / 180);

    double bil(double Function(int, int) f) =>
        f(i0, j0) * (1 - tx) * (1 - ty) +
        f(i0, j1) * (1 - tx) * ty +
        f(i1, j0) * tx * (1 - ty) +
        f(i1, j1) * tx * ty;

    return (bil(u), bil(v));
  }
}

// ── Particle ──────────────────────────────────────────────────────────────────
class _Particle {
  double lat, lon;
  int age = 0;
  final List<(double, double)> trail = [];

  static const trailLen = 12;
  static const maxAge = 180;

  _Particle(this.lat, this.lon);

  factory _Particle.random(
      math.Random rng, double s, double n, double w, double e) =>
      _Particle(s + rng.nextDouble() * (n - s),
                w + rng.nextDouble() * (e - w));

  void step(_WindGrid field, double dt) {
    trail.add((lat, lon));
    if (trail.length > trailLen) trail.removeAt(0);

    final uv = field.uv(lat, lon);
    if (uv == null) { age = maxAge; return; }
    final (u, v) = uv;

    // 8 000× visual speedup so flow is visible at map zoom 8
    const k = 0.447 / 111000 * 8000;
    lat += v * k * dt;
    lon += u * k * dt / math.max(0.1, math.cos(lat * math.pi / 180));
    age++;
  }

  double get opacity {
    const fi = 20, fo = 30;
    if (age < fi) return age / fi;
    if (age > maxAge - fo) return (maxAge - age) / fo;
    return 1.0;
  }
}

// ── Particle layer ────────────────────────────────────────────────────────────
class _WindParticleLayer extends StatefulWidget {
  final _WindGrid? field;
  const _WindParticleLayer({super.key, required this.field});

  @override
  State<_WindParticleLayer> createState() => _WindParticleLayerState();
}

class _WindParticleLayerState extends State<_WindParticleLayer>
    with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  final _rng = math.Random();
  late final Ticker _ticker;
  Duration? _lastTick;
  static const _maxParticles = 300;

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
    const pad = 0.35;

    for (final p in _particles) {
      p.step(widget.field!, dt.clamp(0.005, 0.05));
    }

    _particles.removeWhere((p) =>
        p.age >= _Particle.maxAge ||
        p.lat < b.south - pad || p.lat > b.north + pad ||
        p.lon < b.west - pad || p.lon > b.east + pad);

    while (_particles.length < _maxParticles) {
      _particles.add(
          _Particle.random(_rng, b.south, b.north, b.west, b.east));
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ParticlePainter(
        List.unmodifiable(_particles),
        MapCamera.of(context),
        widget.field,
      ),
      child: const SizedBox.expand(),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final MapCamera camera;
  final _WindGrid? field;
  _ParticlePainter(this.particles, this.camera, this.field);

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
      final base = _speedColor(speed);

      final allPts = [...p.trail.map((t) => _s(t.$1, t.$2)),
                      _s(p.lat, p.lon)];

      // Fading trail — each segment grows thicker and more opaque toward head
      for (var i = 1; i < allPts.length; i++) {
        final frac = i / allPts.length;
        canvas.drawLine(
          allPts[i - 1],
          allPts[i],
          linePaint
            ..color = base.withOpacity((frac * p.opacity * 0.95).clamp(0, 1))
            ..strokeWidth = 0.6 + frac * 1.6,
        );
      }

      // Bright head dot
      if (allPts.isNotEmpty) {
        canvas.drawCircle(
          allPts.last,
          1.8,
          Paint()..color = base.withOpacity(p.opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter _) => true;
}

// ── Screen ────────────────────────────────────────────────────────────────────
class WindMapScreen extends StatefulWidget {
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
  State<WindMapScreen> createState() => _WindMapScreenState();
}

class _WindMapScreenState extends State<WindMapScreen> {
  final _mapController = MapController();
  _WindGrid? _field;
  bool _loading = true;
  String? _error;

  static const _n = 7;
  static const _step = 0.5;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
  ));

  @override
  void initState() {
    super.initState();
    _fetchGrid();
  }

  Future<void> _fetchGrid() async {
    setState(() { _loading = true; _error = null; });
    final half = (_n ~/ 2) * _step;
    final latMin = widget.lat - half;
    final lonMin = widget.lon - half;

    final coords = [
      for (var i = 0; i < _n; i++)
        for (var j = 0; j < _n; j++)
          (latMin + i * _step, lonMin + j * _step)
    ];

    try {
      final results = await Future.wait(coords.map((c) => _fetch(c.$1, c.$2)));
      final pts = results.map((r) => r ?? const _WP(0, 0)).toList();
      if (mounted) {
        setState(() {
          _field = _WindGrid(pts, latMin, lonMin, _step, _n);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Failed to load wind data'; _loading = false; });
    }
  }

  Future<_WP?> _fetch(double lat, double lon) async {
    try {
      final r = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': lat.toStringAsFixed(4),
          'longitude': lon.toStringAsFixed(4),
          'current': 'wind_speed_10m,wind_direction_10m',
          'wind_speed_unit': 'mph',
          'forecast_days': '1',
        },
      );
      final c = r.data['current'] as Map?;
      final s = (c?['wind_speed_10m'] as num?)?.toDouble();
      final d = (c?['wind_direction_10m'] as num?)?.toDouble();
      if (s == null || d == null) return null;
      return _WP(s, d);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.stationName.toUpperCase()} — WIND MAP',
          style: const TextStyle(color: kCyan, fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kCyan),
            tooltip: 'Refresh',
            onPressed: _fetchGrid,
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
            ),
            children: [
              TileLayer(
                // Dark base map — wind colours pop against the dark background
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.mattbettinger.tides',
                retinaMode: true,
              ),
              if (_field != null) _WindParticleLayer(field: _field),
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
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: kCyan),
                    SizedBox(height: 12),
                    Text('Loading wind data…',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          if (!_loading && _error == null) _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() => Positioned(
        bottom: 40,
        left: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(const Color(0xFF98ECFF)),
              _label('<5'),
              _dot(const Color(0xFF56E39F)),
              _label('5–15'),
              _dot(const Color(0xFFF9CA24)),
              _label('15–25'),
              _dot(const Color(0xFFF0932B)),
              _label('25–35'),
              _dot(const Color(0xFFEB4D4B)),
              _label('>35 mph'),
            ],
          ),
        ),
      );

  Widget _dot(Color c) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 3, right: 3),
        child: Text(t,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
      );
}
