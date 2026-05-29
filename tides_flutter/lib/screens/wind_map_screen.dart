import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';

const _gridSpacing = 0.4;
const _gridSize = 5;

class _WindPoint {
  final LatLng position;
  final double speedMph;
  final double dirFrom;
  const _WindPoint(this.position, this.speedMph, this.dirFrom);
}

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
  List<_WindPoint> _points = [];
  bool _loading = true;
  String? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });

    final half = (_gridSize ~/ 2) * _gridSpacing;
    final coords = <LatLng>[];
    for (var i = 0; i < _gridSize; i++) {
      for (var j = 0; j < _gridSize; j++) {
        coords.add(LatLng(
          widget.lat - half + i * _gridSpacing,
          widget.lon - half + j * _gridSpacing,
        ));
      }
    }

    try {
      final results = await Future.wait(
        coords.map((c) => _fetchWind(c.latitude, c.longitude)),
      );

      final points = <_WindPoint>[];
      for (var i = 0; i < coords.length; i++) {
        final r = results[i];
        if (r != null) points.add(_WindPoint(coords[i], r.$1, r.$2));
      }

      if (mounted) setState(() { _points = points; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load wind data'; _loading = false; });
    }
  }

  Future<(double, double)?> _fetchWind(double lat, double lon) async {
    try {
      final resp = await _dio.get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': lat.toStringAsFixed(4),
          'longitude': lon.toStringAsFixed(4),
          'current': 'wind_speed_10m,wind_direction_10m',
          'wind_speed_unit': 'mph',
          'forecast_days': '1',
        },
      );
      final current = resp.data['current'] as Map?;
      if (current == null) return null;
      final speed = (current['wind_speed_10m'] as num?)?.toDouble();
      final dir = (current['wind_direction_10m'] as num?)?.toDouble();
      if (speed == null || dir == null) return null;
      return (speed, dir);
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mattbettinger.tides',
              ),
              if (_points.isNotEmpty)
                MarkerLayer(
                  markers: _points
                      .map((p) => Marker(
                            point: p.position,
                            width: 52,
                            height: 52,
                            child: _WindArrow(p.speedMph, p.dirFrom),
                          ))
                      .toList(),
                ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                  TextSourceAttribution('Open-Meteo'),
                ],
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black54,
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
          if (!_loading && _error == null)
            Positioned(
              bottom: 40,
              left: 12,
              child: _WindLegend(),
            ),
        ],
      ),
    );
  }
}

class _WindArrow extends StatelessWidget {
  final double speedMph;
  final double dirFrom;
  const _WindArrow(this.speedMph, this.dirFrom);

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _WindArrowPainter(speedMph, dirFrom),
        size: const Size(52, 52),
      );
}

class _WindArrowPainter extends CustomPainter {
  final double speedMph;
  final double dirFrom;
  _WindArrowPainter(this.speedMph, this.dirFrom);

  Color get _color {
    if (speedMph < 10) return const Color(0xFF4CAF50);
    if (speedMph < 20) return const Color(0xFFFFEB3B);
    if (speedMph < 30) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = Colors.black.withOpacity(0.55),
    );

    // Arrow points toward where wind is blowing (FROM + 180°)
    final towardDeg = (dirFrom + 180) % 360;
    final angle = (towardDeg - 90) * math.pi / 180;

    final shaft = r * 0.62;
    final tipX = cx + shaft * math.cos(angle);
    final tipY = cy + shaft * math.sin(angle);
    final tailX = cx - shaft * 0.55 * math.cos(angle);
    final tailY = cy - shaft * 0.55 * math.sin(angle);

    final paint = Paint()
      ..color = _color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(tailX, tailY), Offset(tipX, tipY), paint);

    const headLen = 7.0;
    const headAngle = 0.45;
    canvas.drawLine(
      Offset(tipX, tipY),
      Offset(tipX - headLen * math.cos(angle - headAngle),
          tipY - headLen * math.sin(angle - headAngle)),
      paint,
    );
    canvas.drawLine(
      Offset(tipX, tipY),
      Offset(tipX - headLen * math.cos(angle + headAngle),
          tipY - headLen * math.sin(angle + headAngle)),
      paint,
    );

    // Speed label
    final tp = TextPainter(
      text: TextSpan(
        text: speedMph.round().toString(),
        style: TextStyle(
            color: _color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_WindArrowPainter old) =>
      old.speedMph != speedMph || old.dirFrom != dirFrom;
}

class _WindLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(const Color(0xFF4CAF50)),
            const SizedBox(width: 4),
            const Text('<10',
                style: TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(width: 8),
            _dot(const Color(0xFFFFEB3B)),
            const SizedBox(width: 4),
            const Text('10–20',
                style: TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(width: 8),
            _dot(const Color(0xFFFF9800)),
            const SizedBox(width: 4),
            const Text('20–30',
                style: TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(width: 8),
            _dot(const Color(0xFFF44336)),
            const SizedBox(width: 4),
            const Text('>30 mph',
                style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      );

  Widget _dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );
}
