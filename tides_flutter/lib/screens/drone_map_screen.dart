import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../theme.dart';

enum _AirspaceStatus { loading, clear, controlled, restricted, error }

// Zone type conventions:
//   FAA:   P* prohibited · R* restricted · W*/A* warning/alert · B/C/D class
//   NPS:   'NPS'   → national park / seashore / monument / etc.
//   TFR:   'TFR'   → active FAA Temporary Flight Restriction
//   USFWS: 'USFWS' → national wildlife refuge (permit required)
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

  _AirspaceStatus _gpsStatus = _AirspaceStatus.loading;
  String _gpsHeadline = 'Getting your location…';
  String? _gpsDetail;
  double? _lat, _lon;

  LatLng? _tappedPoint;
  _AirspaceStatus _tapStatus = _AirspaceStatus.loading;
  String _tapHeadline = '';
  String? _tapDetail;
  bool _tapLoading = false;

  List<_AirspaceZone> _zones = [];
  bool _zonesLoading = false;

  _AirspaceStatus get _displayStatus =>
      _tappedPoint != null ? _tapStatus : _gpsStatus;
  String get _displayHeadline =>
      _tappedPoint != null ? _tapHeadline : _gpsHeadline;
  String? get _displayDetail =>
      _tappedPoint != null ? _tapDetail : _gpsDetail;

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

  // ── GPS load ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _tappedPoint = null;
      _gpsStatus = _AirspaceStatus.loading;
      _gpsHeadline = 'Getting your location…';
      _gpsDetail = null;
      _zones = [];
    });

    final loc = await getLocation();
    if (!mounted) return;

    if (loc == null) {
      setState(() {
        _gpsStatus = _AirspaceStatus.error;
        _gpsHeadline = 'Could not get location';
        _gpsDetail =
            'Check that GPS or location services are enabled, then retry.';
      });
      return;
    }

    final (lat, lon, _) = loc;
    setState(() {
      _lat = lat;
      _lon = lon;
      _gpsHeadline = 'Checking airspace…';
    });
    if (_mapReady) _mapController.move(LatLng(lat, lon), 11.0);

    await Future.wait([
      _queryPoint(lat, lon, forGps: true),
      _fetchViewportZones(_boundsAround(lat, lon, 0.55)),
    ]);
  }

  // ── Map tap ────────────────────────────────────────────────────────────────

  Future<void> _onMapTap(TapPosition _, LatLng point) async {
    setState(() {
      _tappedPoint = point;
      _tapLoading = true;
      _tapStatus = _AirspaceStatus.loading;
      _tapHeadline = 'Checking airspace…';
      _tapDetail = null;
    });
    await _queryPoint(point.latitude, point.longitude, forGps: false);
    if (mounted) setState(() => _tapLoading = false);
  }

  void _clearTap() => setState(() => _tappedPoint = null);

  // ── Combined point query: FAA + NPS + TFR + USFWS ─────────────────────────

  Future<void> _queryPoint(double lat, double lon,
      {required bool forGps}) async {
    try {
      final results = await Future.wait([
        _queryFAA(lat, lon),
        _queryNPS(lat, lon),
        _queryTFR(lat, lon),
        _queryUSFWS(lat, lon),
      ]);

      if (!mounted) return;

      final st = _combineStatus(
        results[0] as _FAA,
        results[1] as _NPS,
        results[2] as _TFR,
        results[3] as _USFWS,
      );

      setState(() {
        if (forGps) {
          _gpsStatus = st.status;
          _gpsHeadline = st.headline;
          _gpsDetail = st.detail;
        } else {
          _tapStatus = st.status;
          _tapHeadline = st.headline;
          _tapDetail = st.detail;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        const s = _AirspaceStatus.error;
        const h = 'Airspace data unavailable';
        const d = 'Could not reach the airspace service. Check your connection.';
        if (forGps) {
          _gpsStatus = s;
          _gpsHeadline = h;
          _gpsDetail = d;
        } else {
          _tapStatus = s;
          _tapHeadline = h;
          _tapDetail = d;
        }
      });
    }
  }

  // ── FAA airspace point query ───────────────────────────────────────────────

  Future<_FAA> _queryFAA(double lat, double lon) async {
    bool hasProhibited = false, hasRestricted = false, hasControlled = false;
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
            'f': 'json',
          },
        );
        for (final f in _features(resp.data)) {
          final attrs = _attrs(f);
          final type = _str(attrs, ['TYPE_CODE', 'LOCAL_TYPE']);
          final name = _str(attrs, ['NAME']);
          if (type.startsWith('P')) hasProhibited = true;
          else if (type.startsWith('R') || type.startsWith('W')) hasRestricted = true;
          else hasControlled = true;
          if (name.isNotEmpty) names.add(name);
        }
      } catch (_) {}
    }

    return _FAA(
      hasProhibited: hasProhibited,
      hasRestricted: hasRestricted,
      hasControlled: hasControlled,
      names: names.toSet().take(3).toList(),
    );
  }

  // ── NPS boundary point query ───────────────────────────────────────────────
  // Drones prohibited under 36 CFR 1.5 in all NPS units regardless of
  // FAA airspace class — NPS is a land-management rule, not an airspace rule.

  Future<_NPS> _queryNPS(double lat, double lon) async {
    try {
      final resp = await _dio.get(
        'https://services1.arcgis.com/fBc8EJBxQRMcHlei/arcgis/rest/services/'
        'NPS_Land_Resources_Division_Boundary_and_Tract_Data_Service/'
        'FeatureServer/2/query',
        queryParameters: {
          'geometry': '$lon,$lat',
          'geometryType': 'esriGeometryPoint',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'outFields': 'UNIT_NAME,UNIT_TYPE',
          'returnGeometry': 'false',
          'f': 'json',
        },
      );
      final features = _features(resp.data);
      if (features.isEmpty) return const _NPS(inside: false);
      final attrs = _attrs(features.first);
      final name = _str(attrs, ['UNIT_NAME', 'UNIT_TYPE']);
      return _NPS(inside: true, name: name.isNotEmpty ? name : 'National Park Unit');
    } catch (_) {
      return const _NPS(inside: false);
    }
  }

  // ── TFR point query ────────────────────────────────────────────────────────
  // Active Temporary Flight Restrictions from the FAA ATCSCC service.
  // TFRs are time-limited and not in the static Airspace MapServer — they
  // cover wildfires, presidential movements, sporting events, disasters, etc.
  // checkFailed=true means the service was unreachable; we surface a warning
  // rather than silently showing "clear."

  Future<_TFR> _queryTFR(double lat, double lon) async {
    try {
      final resp = await _dio.get(
        'https://geoservices.faa.gov/arcgis/rest/services/'
        'ATCSCC/TFRS/MapServer/0/query',
        queryParameters: {
          'geometry': '$lon,$lat',
          'geometryType': 'esriGeometryPoint',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'outFields': 'CALLSIGN,TYPE_CODE,REASON',
          'returnGeometry': 'false',
          'f': 'json',
        },
      );
      final features = _features(resp.data);
      if (features.isEmpty) return const _TFR(inside: false);
      final attrs = _attrs(features.first);
      final name = _str(attrs, ['CALLSIGN', 'REASON', 'TYPE_CODE']);
      return _TFR(inside: true, name: name.isNotEmpty ? name : 'Active TFR');
    } on DioException catch (e) {
      // 4xx/5xx or service down → flag as unchecked so the UI warns the user
      final isServiceError = e.response?.statusCode != null;
      return _TFR(inside: false, checkFailed: isServiceError || e.type == DioExceptionType.connectionTimeout);
    } catch (_) {
      return const _TFR(inside: false, checkFailed: true);
    }
  }

  // ── USFWS National Wildlife Refuge point query ─────────────────────────────
  // Drones require a Special Use Permit on most refuges; many explicitly
  // prohibit them. Highly relevant for fishing drones near coastal wetlands.

  Future<_USFWS> _queryUSFWS(double lat, double lon) async {
    try {
      final resp = await _dio.get(
        'https://gis.fws.gov/arcgis/rest/services/'
        'FWS_Boundaries/FeatureServer/0/query',
        queryParameters: {
          'geometry': '$lon,$lat',
          'geometryType': 'esriGeometryPoint',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'outFields': 'ORGNAME,STA_NM,AREANAME',
          'returnGeometry': 'false',
          'f': 'json',
        },
      );
      final features = _features(resp.data);
      if (features.isEmpty) return const _USFWS(inside: false);
      final attrs = _attrs(features.first);
      final name = _str(attrs, ['ORGNAME', 'STA_NM', 'AREANAME']);
      return _USFWS(inside: true, name: name.isNotEmpty ? name : 'National Wildlife Refuge');
    } catch (_) {
      return const _USFWS(inside: false);
    }
  }

  // ── Status combiner ────────────────────────────────────────────────────────
  // Priority: FAA prohibited → active TFR → NPS → FAA restricted →
  //           USFWS refuge → FAA controlled → clear

  _StatusResult _combineStatus(_FAA faa, _NPS nps, _TFR tfr, _USFWS usfws) {
    final extras = <String>[];
    if (nps.inside) extras.add('NPS: ${nps.name ?? 'National Park Unit'} (36 CFR 1.5)');
    if (usfws.inside) extras.add('USFWS: ${usfws.name ?? 'Wildlife Refuge'} (permit required)');
    if (faa.names.isNotEmpty) extras.add('FAA: ${faa.names.join(', ')}');

    final tfrNote = tfr.checkFailed
        ? '\n⚠ TFR status could not be verified — check FAA NOTAM system before flying.'
        : '';

    // FAA Prohibited — always no-fly
    if (faa.hasProhibited) {
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: 'Prohibited airspace — no drone operations allowed',
        detail: '${extras.join('\n')}$tfrNote'.trim().nullIfEmpty,
      );
    }

    // Active TFR — temporary no-fly
    if (tfr.inside) {
      final tfrName = tfr.name ?? 'Active TFR';
      final otherExtras = [
        if (nps.inside) 'Also inside NPS unit: ${nps.name ?? ''} (36 CFR 1.5)',
        if (usfws.inside) 'Also in Wildlife Refuge: ${usfws.name ?? ''} (permit required)',
        if (faa.hasRestricted || faa.hasControlled)
          'FAA airspace: ${faa.names.join(', ')}',
      ];
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: 'Active TFR — no drone operations',
        detail: [tfrName, ...otherExtras].join('\n').nullIfEmpty,
      );
    }

    // NPS — prohibited by land-management rule
    if (nps.inside) {
      final park = nps.name ?? 'National Park Unit';
      final extra = [
        if (faa.hasRestricted)
          'Also in FAA restricted airspace: ${faa.names.join(', ')}',
        if (faa.hasControlled)
          'Also in controlled airspace: ${faa.names.join(', ')} (FAA auth required)',
        if (usfws.inside)
          'Also in Wildlife Refuge: ${usfws.name ?? ''} (permit required)',
      ];
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: '$park — drones prohibited',
        detail: ['Prohibited under NPS regulation 36 CFR 1.5, regardless of FAA airspace class.', ...extra, tfrNote.trim()].where((s) => s.isNotEmpty).join('\n').nullIfEmpty,
      );
    }

    // FAA Restricted
    if (faa.hasRestricted) {
      final extra = [
        if (usfws.inside) 'Also in Wildlife Refuge: ${usfws.name ?? ''} (permit required)',
        tfrNote.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: 'Restricted airspace — contact the controlling agency',
        detail: [if (faa.names.isNotEmpty) faa.names.join(', '), extra].where((s) => s.isNotEmpty).join('\n').nullIfEmpty,
      );
    }

    // USFWS Wildlife Refuge
    if (usfws.inside) {
      final refuge = usfws.name ?? 'National Wildlife Refuge';
      final extra = [
        if (faa.hasControlled) 'Also in controlled airspace: ${faa.names.join(', ')} (FAA auth required)',
        tfrNote.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      return _StatusResult(
        status: _AirspaceStatus.controlled,
        headline: '$refuge — Special Use Permit required',
        detail: ['Drones require a USFWS Special Use Permit on national wildlife refuges. Many refuges prohibit drone use entirely — contact the refuge manager before flying.', extra].where((s) => s.isNotEmpty).join('\n').nullIfEmpty,
      );
    }

    // FAA Controlled (Class B/C/D)
    if (faa.hasControlled) {
      final detail = [
        if (faa.names.isNotEmpty)
          '${faa.names.join(', ')}\nDrones require FAA authorization before flying here.'
        else
          'Drones require FAA authorization before flying here.',
        tfrNote.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      return _StatusResult(
        status: _AirspaceStatus.controlled,
        headline: 'Controlled airspace — FAA authorization required',
        detail: detail.nullIfEmpty,
      );
    }

    // Clear — Class G, no NPS, no TFR, no refuge
    return _StatusResult(
      status: _AirspaceStatus.clear,
      headline: 'Class G — uncontrolled airspace',
      detail: ['No restricted airspace, national park, wildlife refuge, or active TFR detected at this location.', 'Fly under 400 ft AGL, keep the drone in sight, and stay clear of people, vehicles, and emergency scenes.', tfrNote.trim()].where((s) => s.isNotEmpty).join('\n').nullIfEmpty,
    );
  }

  // ── Viewport bbox query (polygon overlay) ─────────────────────────────────

  LatLngBounds _boundsAround(double lat, double lon, double deg) =>
      LatLngBounds(LatLng(lat - deg, lon - deg), LatLng(lat + deg, lon + deg));

  Future<void> _fetchViewportZones(LatLngBounds bounds) async {
    if (!mounted) return;
    setState(() => _zonesLoading = true);

    final minLon = bounds.west;
    final minLat = bounds.south;
    final maxLon = bounds.east;
    final maxLat = bounds.north;
    final bbox = '$minLon,$minLat,$maxLon,$maxLat';

    final zones = <_AirspaceZone>[];

    await Future.wait([
      // FAA Class B/C/D/E
      _bboxQuery(
        'https://geoservices.faa.gov/arcgis/rest/services/Aeronautical/Airspace/MapServer/0/query',
        bbox, 'FAA', ['TYPE_CODE', 'LOCAL_TYPE'], ['NAME'], zones,
      ),
      // FAA Special Use (Restricted/Prohibited/Warning/Alert)
      _bboxQuery(
        'https://geoservices.faa.gov/arcgis/rest/services/Aeronautical/Airspace/MapServer/1/query',
        bbox, 'FAA', ['TYPE_CODE', 'LOCAL_TYPE'], ['NAME'], zones,
      ),
      // NPS boundaries
      _bboxQuery(
        'https://services1.arcgis.com/fBc8EJBxQRMcHlei/arcgis/rest/services/'
        'NPS_Land_Resources_Division_Boundary_and_Tract_Data_Service/FeatureServer/2/query',
        bbox, 'NPS', [], ['UNIT_NAME', 'UNIT_TYPE'], zones,
      ),
      // Active TFRs
      _bboxQuery(
        'https://geoservices.faa.gov/arcgis/rest/services/ATCSCC/TFRS/MapServer/0/query',
        bbox, 'TFR', [], ['CALLSIGN', 'REASON', 'TYPE_CODE'], zones,
      ),
      // USFWS Wildlife Refuges
      _bboxQuery(
        'https://gis.fws.gov/arcgis/rest/services/FWS_Boundaries/FeatureServer/0/query',
        bbox, 'USFWS', [], ['ORGNAME', 'STA_NM', 'AREANAME'], zones,
      ),
    ]);

    if (!mounted) return;
    setState(() {
      _zones = zones;
      _zonesLoading = false;
    });
  }

  Future<void> _bboxQuery(
    String url,
    String bbox,
    String zoneType,
    List<String> typeFields,
    List<String> nameFields,
    List<_AirspaceZone> out,
  ) async {
    try {
      final allFields = {...typeFields, ...nameFields}.join(',');
      final resp = await _dio.get(url, queryParameters: {
        'geometry': bbox,
        'geometryType': 'esriGeometryEnvelope',
        'inSR': '4326',
        'spatialRel': 'esriSpatialRelIntersects',
        'outFields': allFields,
        'returnGeometry': 'true',
        'outSR': '4326',
        'simplifyTolerance': '0.003',
        'f': 'json',
      });

      for (final f in _features(resp.data)) {
        final attrs = _attrs(f);
        final type = typeFields.isNotEmpty
            ? _str(attrs, typeFields).let((t) => t.isNotEmpty ? t : zoneType)
            : zoneType;
        final name = _str(attrs, nameFields).let((n) => n.isNotEmpty ? n : zoneType);
        final geom = f['geometry'] as Map<String, dynamic>?;

        for (final ring in ((geom?['rings'] as List?) ?? []).take(4)) {
          final pts = <LatLng>[];
          for (final raw in (ring as List).take(500)) {
            final c = raw as List;
            if (c.length >= 2) {
              pts.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
          if (pts.length >= 3) out.add(_AirspaceZone(name, type, pts));
        }
      }
    } catch (_) {}
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _fetchViewportZones(camera.visibleBounds);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List _features(dynamic data) =>
      ((data as Map<String, dynamic>)['features'] as List?) ?? [];

  Map<String, dynamic> _attrs(dynamic f) =>
      (f['attributes'] as Map<String, dynamic>?) ?? {};

  String _str(Map<String, dynamic> attrs, List<String> keys) {
    for (final k in keys) {
      final v = attrs[k]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  // ── Zone colors ───────────────────────────────────────────────────────────

  Color _zoneFill(String type) {
    if (type == 'TFR')   return const Color(0x44FFB800);
    if (type == 'USFWS') return const Color(0x2D9B30FF);
    if (type == 'NPS')   return const Color(0x2D1B7F00);
    if (type.startsWith('P')) return const Color(0x55DD0000);
    if (type.startsWith('R')) return const Color(0x3DDD0000);
    if (type.startsWith('W') || type.startsWith('A')) return Colors.orange.withValues(alpha: 0.22);
    if (type.contains('B')) return const Color(0x330070C0);
    if (type.contains('C')) return const Color(0x33AA00FF);
    if (type.contains('D')) return const Color(0x220070C0);
    return Colors.orange.withValues(alpha: 0.14);
  }

  Color _zoneBorder(String type) {
    if (type == 'TFR')   return const Color(0xFFFFB800);
    if (type == 'USFWS') return const Color(0xFF7B10EE);
    if (type == 'NPS')   return const Color(0xFF1B7F00);
    if (type.startsWith('P') || type.startsWith('R')) return const Color(0xFFCC2200);
    if (type.startsWith('W') || type.startsWith('A')) return Colors.orange;
    if (type.contains('B')) return const Color(0xFF0070C0);
    if (type.contains('C')) return const Color(0xFFAA00FF);
    if (type.contains('D')) return const Color(0xFF0070C0);
    return Colors.orange;
  }

  double _zoneBorderWidth(String type) =>
      (type == 'NPS' || type == 'USFWS') ? 1.5 : 2.0;

  // Draw order: USFWS → NPS → FAA → TFR (most urgent on top)
  List<_AirspaceZone> _zonesOfType(String type) =>
      _zones.where((z) => z.type == type && z.ring.length >= 3).toList();

  List<_AirspaceZone> _faaZones() =>
      _zones.where((z) => !const {'NPS', 'TFR', 'USFWS'}.contains(z.type) && z.ring.length >= 3).toList();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lat = _lat ?? 29.5;
    final lon = _lon ?? -90.0;

    final usfwsZ = _zonesOfType('USFWS');
    final npsZ   = _zonesOfType('NPS');
    final faaZ   = _faaZones();
    final tfrZ   = _zonesOfType('TFR');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavy,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Before You Fly',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_zonesLoading || _tapLoading)
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
                if (_lat != null) _mapController.move(LatLng(_lat!, _lon!), 11.0);
              },
              onPositionChanged: _onPositionChanged,
              onTap: _onMapTap,
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
              for (final group in [usfwsZ, npsZ, faaZ, tfrZ])
                if (group.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final z in group)
                        Polygon(
                          points: z.ring,
                          color: _zoneFill(z.type),
                          borderColor: _zoneBorder(z.type),
                          borderStrokeWidth: _zoneBorderWidth(z.type),
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
                    width: 18, height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.50), blurRadius: 8)],
                      ),
                    ),
                  ),
                ]),
              ],
              if (_tappedPoint != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _tappedPoint!,
                    width: 32, height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: kCyan, size: 36,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                  ),
                ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© CARTO'),
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('FAA · NPS · USFWS'),
                ],
              ),
            ],
          ),
          if (_tappedPoint == null && _gpsStatus != _AirspaceStatus.loading)
            Positioned(
              top: 12, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'Tap anywhere on the map to check that location',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _StatusCard(
              status: _displayStatus,
              headline: _displayHeadline,
              detail: _displayDetail,
              isTappedLocation: _tappedPoint != null,
              onRetry: _load,
              onClearTap: _clearTap,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _FAA {
  final bool hasProhibited, hasRestricted, hasControlled;
  final List<String> names;
  const _FAA({
    required this.hasProhibited,
    required this.hasRestricted,
    required this.hasControlled,
    required this.names,
  });
}

class _NPS {
  final bool inside;
  final String? name;
  const _NPS({required this.inside, this.name});
}

class _TFR {
  final bool inside;
  final bool checkFailed;
  final String? name;
  const _TFR({required this.inside, this.checkFailed = false, this.name});
}

class _USFWS {
  final bool inside;
  final String? name;
  const _USFWS({required this.inside, this.name});
}

class _StatusResult {
  final _AirspaceStatus status;
  final String headline;
  final String? detail;
  const _StatusResult({required this.status, required this.headline, this.detail});
}

// ── Extensions ────────────────────────────────────────────────────────────────

extension _StringX on String {
  String? get nullIfEmpty => isEmpty ? null : this;
  T let<T>(T Function(String) fn) => fn(this);
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final _AirspaceStatus status;
  final String headline;
  final String? detail;
  final bool isTappedLocation;
  final VoidCallback onRetry;
  final VoidCallback onClearTap;

  const _StatusCard({
    required this.status,
    required this.headline,
    this.detail,
    required this.isTappedLocation,
    required this.onRetry,
    required this.onClearTap,
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
          border: Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: const [
                _LegendChip(color: Color(0x55DD0000), border: Color(0xFFCC2200), label: 'Prohibited'),
                SizedBox(width: 6),
                _LegendChip(color: Color(0x3DDD0000), border: Color(0xFFCC2200), label: 'Restricted'),
                SizedBox(width: 6),
                _LegendChip(color: Color(0x44FFB800), border: Color(0xFFFFB800), label: 'Active TFR'),
                SizedBox(width: 6),
                _LegendChip(color: Color(0x44FF8C00), border: Colors.orange,    label: 'Warning'),
                SizedBox(width: 6),
                _LegendChip(color: Color(0x330070C0), border: Color(0xFF0070C0), label: 'Class B/C/D'),
                SizedBox(width: 6),
                _LegendChip(color: Color(0x2D1B7F00), border: Color(0xFF1B7F00), label: 'Nat\'l Park'),
                SizedBox(width: 6),
                _LegendChip(color: Color(0x2D9B30FF), border: Color(0xFF7B10EE), label: 'Wildlife Refuge'),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(
                isTappedLocation ? Icons.place : Icons.my_location,
                size: 13,
                color: isTappedLocation ? kCyan : Colors.blue,
              ),
              const SizedBox(width: 4),
              Text(
                isTappedLocation ? 'Tapped location' : 'Your GPS location',
                style: TextStyle(
                  color: isTappedLocation ? kCyan : Colors.blue[200],
                  fontSize: 11, fontWeight: FontWeight.w500,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status == _AirspaceStatus.loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: kCyan, strokeWidth: 2),
                    ),
                  )
                else
                  Icon(statusIcon, color: textColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    headline,
                    style: TextStyle(
                        color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(detail!,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4)),
              ),
            ],
            const SizedBox(height: 12),
            if (isTappedLocation)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.my_location, size: 15),
                    label: const Text('My Location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[200],
                      side: BorderSide(color: Colors.blue[300]!.withValues(alpha: 0.6)),
                    ),
                    onPressed: onClearTap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Check Again'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kCyan,
                      side: const BorderSide(color: kCyan),
                    ),
                    onPressed: onRetry,
                  ),
                ),
              ])
            else
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
              'Data: FAA airspace · FAA TFRs · NPS boundaries · USFWS refuge boundaries. '
              'For reference only — always confirm with FAA NOTAM system before flying.',
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
  const _LegendChip({required this.color, required this.border, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: border, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      );
}
