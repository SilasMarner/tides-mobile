import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../theme.dart';

enum _AirspaceStatus { loading, clear, controlled, restricted, error }

class _AirspaceZone {
  final String name;
  final String type;
  final List<LatLng> ring;
  const _AirspaceZone(this.name, this.type, this.ring);
}

class DroneMapScreen extends StatefulWidget {
  const DroneMapScreen({super.key});

  @override
  State<DroneMapScreen> createState() => _DroneMapScreenState();
}

class _DroneMapScreenState extends State<DroneMapScreen> {
  final _mapController = MapController();
  bool _mapReady = false;
  Timer? _viewportDebounce;

  _AirspaceStatus _status = _AirspaceStatus.loading;
  String _headline = 'Getting your location…';
  String? _detail;
  double? _lat, _lon;
  List<_AirspaceZone> _zones = [];
  bool _zonesLoading = false;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _viewportDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _status = _AirspaceStatus.loading;
      _headline = 'Getting your location…';
      _detail = null;
      _zones = [];
    });

    final loc = await getLocation();
    if (!mounted) return;

    if (loc == null) {
      setState(() {
        _status = _AirspaceStatus.error;
        _headline = 'Could not get location';
        _detail = 'Check that GPS or location services are enabled, then retry.';
      });
      return;
    }

    final (lat, lon, _) = loc;
    setState(() {
      _lat = lat;
      _lon = lon;
      _headline = 'Checking FAA airspace…';
    });
    if (_mapReady) _mapController.move(LatLng(lat, lon), 11.0);

    // Point query drives the status card; bbox query fills the map overlay.
    // Run concurrently — both use the same FAA endpoint, different geometries.
    await Future.wait([
      _checkStatus(lat, lon),
      _fetchViewportZones(_boundsAround(lat, lon, 0.55)),
    ]);
  }

  LatLngBounds _boundsAround(double lat, double lon, double deg) =>
      LatLngBounds(LatLng(lat - deg, lon - deg), LatLng(lat + deg, lon + deg));

  // Point intersection → drives status card headline only (no geometry needed).
  Future<void> _checkStatus(double lat, double lon) async {
    try {
      bool hasProhibited = false;
      bool hasRestricted = false;
      bool hasControlled = false;
      final names = <String>[];

      for (final layerId in [0, 1]) {
        try {
          final resp = await _dio.get(
            'https://geoservices.faa.gov/arcgis/rest/services/'
            'Aeronautical/Airspace/MapServer/$layerId/query',
            queryParameters: {
              'geometry': '$lon,$lat',
              'geometryType': 'esriGeometryPoint',
              'inSR': '4326',
              'spatialRel': 'esriSpatialRelIntersects',
              'outFields': 'TYPE_CODE,LOCAL_TYPE,NAME',
              'returnGeometry': 'false',
              'outSR': '4326',
              'f': 'json',
            },
          );

          final data = resp.data as Map<String, dynamic>;
          final features = (data['features'] as List?) ?? [];
          for (final f in features) {
            final attrs = (f['attributes'] as Map<String, dynamic>?) ?? {};
            final type =
                (attrs['TYPE_CODE'] ?? attrs['LOCAL_TYPE'] ?? '').toString();
            final name = (attrs['NAME'] ?? '').toString();
            if (type.startsWith('P')) {
              hasProhibited = true;
            } else if (type.startsWith('R') || type.startsWith('W')) {
              hasRestricted = true;
            } else {
              hasControlled = true;
            }
            if (name.isNotEmpty) names.add(name);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      final nameStr = names.toSet().take(3).join(', ');

      setState(() {
        if (hasProhibited) {
          _status = _AirspaceStatus.restricted;
          _headline = 'Prohibited airspace — no drone operations allowed';
          _detail = nameStr.isNotEmpty ? nameStr : null;
        } else if (hasRestricted) {
          _status = _AirspaceStatus.restricted;
          _headline = 'Restricted airspace — contact the controlling agency';
          _detail = nameStr.isNotEmpty ? nameStr : null;
        } else if (hasControlled) {
          _status = _AirspaceStatus.controlled;
          _headline = 'Controlled airspace — FAA authorization required';
          _detail = nameStr.isNotEmpty
              ? '$nameStr\nDrones require FAA authorization before flying here.'
              : 'Drones require FAA authorization before flying here.';
        } else {
          _status = _AirspaceStatus.clear;
          _headline = 'Class G — uncontrolled airspace';
          _detail = 'No controlled or restricted airspace detected at this '
              'location. FAA rules: fly under 400 ft AGL, keep the drone in '
              'sight, and stay away from people, vehicles, and emergency scenes.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _AirspaceStatus.error;
        _headline = 'Airspace data unavailable';
        _detail =
            'Could not reach the FAA airspace service. Check your connection and retry.';
      });
    }
  }

  // Bbox query → fills the map overlay for the current viewport.
  Future<void> _fetchViewportZones(LatLngBounds bounds) async {
    if (!mounted) return;
    setState(() => _zonesLoading = true);

    final minLon = bounds.west;
    final minLat = bounds.south;
    final maxLon = bounds.east;
    final maxLat = bounds.north;

    final zones = <_AirspaceZone>[];

    for (final layerId in [0, 1]) {
      try {
        final resp = await _dio.get(
          'https://geoservices.faa.gov/arcgis/rest/services/'
          'Aeronautical/Airspace/MapServer/$layerId/query',
          queryParameters: {
            'geometry': '$minLon,$minLat,$maxLon,$maxLat',
            'geometryType': 'esriGeometryEnvelope',
            'inSR': '4326',
            'spatialRel': 'esriSpatialRelIntersects',
            'outFields': 'TYPE_CODE,LOCAL_TYPE,NAME',
            'returnGeometry': 'true',
            'outSR': '4326',
            'simplifyTolerance': '0.003',
            'f': 'json',
          },
        );

        final data = resp.data as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? [];

        for (final f in features) {
          final attrs = (f['attributes'] as Map<String, dynamic>?) ?? {};
          final geom = f['geometry'] as Map<String, dynamic>?;
          final type =
              (attrs['TYPE_CODE'] ?? attrs['LOCAL_TYPE'] ?? '').toString();
          final name = (attrs['NAME'] ?? type).toString();

          final rings = geom?['rings'] as List?;
          if (rings == null) continue;

          for (final ring in rings.take(4)) {
            final pts = <LatLng>[];
            for (final raw in (ring as List).take(500)) {
              final c = raw as List;
              if (c.length >= 2) {
                pts.add(LatLng(
                    (c[1] as num).toDouble(), (c[0] as num).toDouble()));
              }
            }
            if (pts.length >= 3) zones.add(_AirspaceZone(name, type, pts));
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _zones = zones;
      _zonesLoading = false;
    });
  }

  // Re-fetch the overlay when the user pans or zooms the map.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _fetchViewportZones(camera.visibleBounds);
    });
  }

  // Color coding:
  //   Prohibited (P)          → solid red tint + red border
  //   Restricted (R) /        → lighter red tint + red border
  //   Warning (W) / Alert (A) → orange tint
  //   Class B                 → blue tint
  //   Class C                 → purple tint
  //   Class D                 → light blue tint
  //   MOA / other             → faint orange
  Color _zoneFill(String type) {
    if (type.startsWith('P')) return const Color(0x55DD0000);
    if (type.startsWith('R')) return const Color(0x3DDD0000);
    if (type.startsWith('W') || type.startsWith('A')) return Colors.orange.withValues(alpha: 0.22);
    if (type.contains('B')) return const Color(0x330070C0);
    if (type.contains('C')) return const Color(0x33AA00FF);
    if (type.contains('D')) return const Color(0x220070C0);
    return Colors.orange.withValues(alpha: 0.14);
  }

  Color _zoneBorder(String type) {
    if (type.startsWith('P') || type.startsWith('R')) return const Color(0xFFCC2200);
    if (type.startsWith('W') || type.startsWith('A')) return Colors.orange;
    if (type.contains('B')) return const Color(0xFF0070C0);
    if (type.contains('C')) return const Color(0xFFAA00FF);
    if (type.contains('D')) return const Color(0xFF0070C0);
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final lat = _lat ?? 29.5;
    final lon = _lon ?? -90.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavy,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Before You Fly',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_zonesLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white54, strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(lat, lon),
              initialZoom: _lat != null ? 11.0 : 5.0,
              minZoom: 3,
              maxZoom: 14,
              onMapReady: () {
                _mapReady = true;
                if (_lat != null) {
                  _mapController.move(LatLng(_lat!, _lon!), 11.0);
                }
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
                panBuffer: 2,
              ),
              // Airspace overlay — redraws as zones update from bbox queries
              if (_zones.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    for (final z in _zones.where((z) => z.ring.length >= 3))
                      Polygon(
                        points: z.ring,
                        color: _zoneFill(z.type),
                        borderColor: _zoneBorder(z.type),
                        borderStrokeWidth: 2.0,
                      ),
                  ],
                ),
              if (_lat != null) ...[
                CircleLayer(circles: [
                  CircleMarker(
                    point: LatLng(lat, lon),
                    radius: 40,
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderColor: Colors.blue.withValues(alpha: 0.40),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: LatLng(lat, lon),
                    width: 18,
                    height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.50),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© CARTO'),
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('Airspace data: FAA'),
                ],
              ),
            ],
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _StatusCard(
              status: _status,
              headline: _headline,
              detail: _detail,
              onRetry: _load,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legend chip ───────────────────────────────────────────────────────────────

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final _AirspaceStatus status;
  final String headline;
  final String? detail;
  final VoidCallback onRetry;

  const _StatusCard({
    required this.status,
    required this.headline,
    this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final (borderColor, statusIcon, textColor) = switch (status) {
      _AirspaceStatus.loading    => (Colors.white24,          Icons.hourglass_empty, Colors.white70),
      _AirspaceStatus.clear      => (const Color(0xFF27AE60), Icons.check_circle,    const Color(0xFF2ECC71)),
      _AirspaceStatus.controlled => (const Color(0xFFE67E22), Icons.warning_amber,   const Color(0xFFF39C12)),
      _AirspaceStatus.restricted => (const Color(0xFFE74C3C), Icons.block,           const Color(0xFFE74C3C)),
      _AirspaceStatus.error      => (Colors.white24,          Icons.wifi_off,        Colors.white54),
    };

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: kNavyLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: borderColor.withValues(alpha: 0.65), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Legend row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const [
                  _LegendChip(color: Color(0x55DD0000), border: Color(0xFFCC2200), label: 'Prohibited'),
                  SizedBox(width: 6),
                  _LegendChip(color: Color(0x3DDD0000), border: Color(0xFFCC2200), label: 'Restricted'),
                  SizedBox(width: 6),
                  _LegendChip(color: Color(0x44FF8C00), border: Colors.orange, label: 'Warning/Alert'),
                  SizedBox(width: 6),
                  _LegendChip(color: Color(0x330070C0), border: Color(0xFF0070C0), label: 'Class B/C/D'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status == _AirspaceStatus.loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: kCyan, strokeWidth: 2),
                    ),
                  )
                else
                  Icon(statusIcon, color: textColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    headline,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  detail!,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.my_location, size: 15),
                label: const Text('Check Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kCyan,
                  side: const BorderSide(color: kCyan),
                ),
                onPressed: onRetry,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Airspace data: FAA public service. For reference only — '
              'regulations change and TFRs are not always captured here. '
              'Always confirm before flying.',
              style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final Color border;
  final String label;

  const _LegendChip({
    required this.color,
    required this.border,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: border, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      );
}
