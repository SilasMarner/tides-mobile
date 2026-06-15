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

  _AirspaceStatus _status = _AirspaceStatus.loading;
  String _headline = 'Getting your location…';
  String? _detail;
  double? _lat, _lon;
  List<_AirspaceZone> _zones = [];

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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

    await _checkAirspace(lat, lon);
  }

  // Queries the FAA's public ArcGIS REST service (no API key, no third-party)
  // at the given point. Layer 0 = Class B/C/D/E surface; layer 1 = Special Use
  // (Restricted / Prohibited / Warning / Alert). Returns polygon geometry so
  // the zones are drawn directly on the map.
  Future<void> _checkAirspace(double lat, double lon) async {
    try {
      final zones = <_AirspaceZone>[];

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
              'outFields': 'TYPE_CODE,LOCAL_TYPE,NAME,LOWER_VAL,UPPER_VAL,UPPER_UOM',
              'returnGeometry': 'true',
              'outSR': '4326',
              'simplifyTolerance': '0.005',
              'f': 'json',
            },
          );

          final data = resp.data as Map<String, dynamic>;
          final features = (data['features'] as List?) ?? [];

          for (final f in features) {
            final attrs = (f['attributes'] as Map<String, dynamic>?) ?? {};
            final geom = f['geometry'] as Map<String, dynamic>?;

            final type = (attrs['TYPE_CODE'] ?? attrs['LOCAL_TYPE'] ?? '').toString();
            final name = (attrs['NAME'] ?? type).toString();

            final rings = geom?['rings'] as List?;
            final pts = <LatLng>[];
            if (rings != null && rings.isNotEmpty) {
              for (final raw in (rings[0] as List).take(300)) {
                final c = raw as List;
                if (c.length >= 2) {
                  pts.add(LatLng(
                      (c[1] as num).toDouble(), (c[0] as num).toDouble()));
                }
              }
            }

            zones.add(_AirspaceZone(name, type, pts));
          }
        } catch (_) {
          // One layer failing doesn't stop the other
        }
      }

      if (!mounted) return;

      if (zones.isEmpty) {
        setState(() {
          _zones = [];
          _status = _AirspaceStatus.clear;
          _headline = 'Class G — uncontrolled airspace';
          _detail = 'No controlled or restricted airspace detected at this location.\n'
              'FAA rules: fly under 400 ft AGL, keep the drone in sight, '
              'and stay away from people, moving vehicles, and emergency scenes.';
        });
      } else {
        final hasProhibited = zones.any((z) => z.type.startsWith('P'));
        final hasRestricted = zones.any((z) => z.type.startsWith('R'));
        final names = zones
            .map((z) => z.name)
            .where((n) => n.isNotEmpty)
            .toSet()
            .take(3)
            .join(', ');

        setState(() {
          _zones = zones;
          if (hasProhibited) {
            _status = _AirspaceStatus.restricted;
            _headline = 'Prohibited airspace — no drone operations allowed';
            _detail = names.isNotEmpty ? names : null;
          } else if (hasRestricted) {
            _status = _AirspaceStatus.restricted;
            _headline = 'Restricted airspace — contact the controlling agency';
            _detail = names.isNotEmpty ? names : null;
          } else {
            _status = _AirspaceStatus.controlled;
            _headline = 'Controlled airspace — FAA authorization required';
            _detail = names.isNotEmpty
                ? '$names\nDrones require FAA authorization before flying here.'
                : 'Drones require FAA authorization before flying here.';
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _AirspaceStatus.error;
        _headline = 'Airspace data unavailable';
        _detail = 'Could not reach the FAA airspace service. '
            'Check your connection and retry.';
      });
    }
  }

  Color _zoneFill(String type) {
    if (type.startsWith('P')) return Colors.red.withValues(alpha: 0.30);
    if (type.startsWith('R') || type.startsWith('W')) return Colors.red.withValues(alpha: 0.18);
    if (type.contains('B')) return const Color(0x330070C0);
    if (type.contains('C')) return const Color(0x33AA00FF);
    if (type.contains('D')) return const Color(0x220070C0);
    return Colors.orange.withValues(alpha: 0.18);
  }

  Color _zoneBorder(String type) {
    if (type.startsWith('P') || type.startsWith('R')) return const Color(0xFFCC2200);
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
              if (_zones.any((z) => z.ring.isNotEmpty))
                PolygonLayer(
                  polygons: [
                    for (final z in _zones.where((z) => z.ring.isNotEmpty))
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
