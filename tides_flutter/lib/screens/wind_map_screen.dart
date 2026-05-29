import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
  final c = m < 0.5 ? const Color(0xFFABB2B9)
          : m < 1.0 ? const Color(0xFF5D6D7E)
          : m < 2.0 ? const Color(0xFF2C3E50)
          : m < 4.0 ? const Color(0xFF1C2833)
          :             const Color(0xFF0E1620);
  return c.withOpacity(0.50);
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
  return c.withOpacity(0.42);
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
  final String valueVar;
  final String? directionVar;
  final Color Function(double) colorFn;
  final List<(Color, String)> legend;
  const _LayerDef({
    required this.label,
    required this.icon,
    required this.isMarine,
    required this.hasFlow,
    required this.valueVar,
    this.directionVar,
    required this.colorFn,
    required this.legend,
  });
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
  ),
  _Layer.waves: _LayerDef(
    label: 'Waves', icon: Icons.waves,
    isMarine: true, hasFlow: true,
    valueVar: 'wave_height', directionVar: 'wave_direction',
    colorFn: _waveColor,
    legend: [
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
      (Color(0xFFABB2B9), '<0.5m'),
      (Color(0xFF5D6D7E), '0.5–1m'),
      (Color(0xFF2C3E50), '1–2m'),
      (Color(0xFF1C2833), '>2m'),
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
      (Color(0xFF2E86C1), '<10°C'),
      (Color(0xFFA9DFBF), '10–20°C'),
      (Color(0xFFF9CA24), '20–30°C'),
      (Color(0xFFEB4D4B), '>30°C'),
    ],
  ),
  _Layer.pressure: _LayerDef(
    label: 'Pressure', icon: Icons.speed,
    isMarine: false, hasFlow: false,
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
  const _WindParticleLayer(
      {super.key, required this.field, required this.colorFn});

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

    for (final p in _particles) {
      p.step(widget.field!, dt.clamp(0.005, 0.05));
    }

    _particles.removeWhere((p) =>
        p.age >= _Particle.maxAge ||
        p.lat < b.south - pad || p.lat > b.north + pad ||
        p.lon < b.west  - pad || p.lon > b.east  + pad);

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
  _Layer _currentLayer = _Layer.wind;
  _DataGrid? _field;
  ui.Image? _gradientImage;
  bool _loading = true;
  String? _error;

  static const _n    = 9;
  static const _step = 0.5;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  @override
  void initState() {
    super.initState();
    _fetchGrid();
  }

  Future<void> _fetchGrid([_Layer? layer]) async {
    final def = _kLayers[layer ?? _currentLayer]!;
    setState(() { _loading = true; _error = null; _field = null; _gradientImage = null; });
    if (layer != null) setState(() => _currentLayer = layer);

    final half   = (_n ~/ 2) * _step;
    final latMin = widget.lat - half;
    final lonMin = widget.lon - half;

    final lats = <String>[], lons = <String>[];
    for (var i = 0; i < _n; i++) {
      for (var j = 0; j < _n; j++) {
        lats.add((latMin + i * _step).toStringAsFixed(4));
        lons.add((lonMin + j * _step).toStringAsFixed(4));
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
        if (mounted) setState(() {
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

      final field = _DataGrid(pts, latMin, lonMin, _step, _n);
      final img = await _buildGradientImage(field, def.colorFn);

      if (mounted) {
        setState(() {
          _field = field;
          _gradientImage = img;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
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
          if (l != _currentLayer) _fetchGrid(l);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final def = _kLayers[_currentLayer]!;
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
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.mattbettinger.tides',
                retinaMode: true,
              ),
              if (_field != null && _gradientImage != null)
                _SmoothGradientLayer(field: _field!, image: _gradientImage!),
              if (_field != null && def.hasFlow)
                _WindParticleLayer(field: _field, colorFn: def.colorFn),
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
                    onPressed: _fetchGrid,
                    child: const Text('Retry',
                        style: TextStyle(color: kCyan)),
                  ),
                ],
              ),
            ),
          if (!_loading && _error == null) _legend(def),
        ],
      ),
    );
  }

  Widget _legend(_LayerDef def) => Positioned(
        bottom: 32,
        left: 12,
        right: 12,
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: def.legend.expand((item) => [
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
                          color: Colors.white60, fontSize: 10)),
                ),
              ]).toList(),
            ),
          ),
        ),
      );
}
