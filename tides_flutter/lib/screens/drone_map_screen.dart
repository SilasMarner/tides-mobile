import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/map_recenter_button.dart';

enum _AirspaceStatus { loading, clear, controlled, restricted, error }

// Zone type conventions:
//   FAA:        P* prohibited · R* restricted · W*/A* warning/alert · B/C/D class
//   NPS:        'NPS'        → national park / seashore / monument (drones prohibited)
//   STATE_PARK: 'STATE_PARK' → state park (check state regulations)
//   TFR:        'TFR'        → active FAA Temporary Flight Restriction
//   USFWS:      'USFWS'      → national wildlife refuge (permit required)
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

  // User-controlled collapse of the bottom status card. Toggled ONLY by tapping
  // the card's handle / the collapsed bar — never by map gestures. The old
  // auto-hide-on-pan behaviour is what made the card appear to bounce; collapse
  // here is purely user-driven, so it can never bounce. Defaults to expanded so
  // the airspace status is always visible when the safety screen first opens.
  bool _cardCollapsed = false;

  // Shows the recenter button once the user pans the GPS location away from the
  // centre of the viewport. The location pin stays anchored where it is; this
  // just offers a one-tap way back. Driven only by panning, never auto-moves.
  bool _showRecenter = false;

  // NPS boundaries loaded from bundled asset (nps_parks.json.gz).
  // These never change between pans — no API call needed for NPS overlay.
  List<_AirspaceZone> _staticNpsZones = [];

  _AirspaceStatus get _displayStatus =>
      _tappedPoint != null ? _tapStatus : _gpsStatus;
  String get _displayHeadline =>
      _tappedPoint != null ? _tapHeadline : _gpsHeadline;
  String? get _displayDetail =>
      _tappedPoint != null ? _tapDetail : _gpsDetail;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 18),
  ));

  @override
  void initState() {
    super.initState();
    _loadStaticNps();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _loadStaticNps() async {
    try {
      final bytes = await rootBundle.load('assets/nps_parks.json.gz');
      final raw = bytes.buffer.asUint8List();
      final decoded = utf8.decode(GZipCodec().decode(raw));
      final data = json.decode(decoded) as Map<String, dynamic>;
      final zones = <_AirspaceZone>[];
      for (final park in (data['parks'] as List)) {
        final name = (park['n'] as String?) ?? 'NPS Unit';
        for (final ring in (park['r'] as List)) {
          final pts = (ring as List)
              .map<LatLng>((p) => LatLng(
                  (p[1] as num).toDouble(), (p[0] as num).toDouble()))
              .toList();
          if (pts.length >= 3) zones.add(_AirspaceZone(name, 'NPS', pts));
        }
      }
      if (mounted) setState(() => _staticNpsZones = zones);
    } catch (e) {
      debugPrint('NPS asset load failed: $e');
    }
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

  // ── Combined point query ───────────────────────────────────────────────────

  Future<void> _queryPoint(double lat, double lon,
      {required bool forGps}) async {
    try {
      final results = await Future.wait([
        _queryFAA(lat, lon),
        _queryProtectedLands(lat, lon),
        _queryTFR(lat, lon),
        _queryUSFWS(lat, lon),
      ]);

      if (!mounted) return;

      final st = _combineStatus(
        results[0] as _FAA,
        results[1] as _ProtectedLand,
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
          _gpsStatus = s; _gpsHeadline = h; _gpsDetail = d;
        } else {
          _tapStatus = s; _tapHeadline = h; _tapDetail = d;
        }
      });
    }
  }

  // ── FAA airspace (layers 0 + 1) ────────────────────────────────────────────

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
          final a = _attrs(f);
          final type = _str(a, ['TYPE_CODE', 'LOCAL_TYPE']);
          final name = _str(a, ['NAME']);
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

  // ── USGS National Map — NPS unit boundaries (layer 29) ───────────────────
  // carto.nationalmap.gov/govunits/MapServer/29 covers all NPS-managed units:
  // national parks, seashores, monuments, recreation areas, historic trails, etc.
  // Drones are prohibited in all NPS units under 36 CFR 1.5.

  Future<_ProtectedLand> _queryProtectedLands(double lat, double lon) async {
    bool insideNPS = false;
    String? npsName;

    try {
      final resp = await _dio.get(
        'https://carto.nationalmap.gov/arcgis/rest/services/'
        'govunits/MapServer/29/query',
        queryParameters: {
          'geometry': '$lon,$lat',
          'geometryType': 'esriGeometryPoint',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'outFields': 'name',
          'returnGeometry': 'false',
          'f': 'json',
        },
      );

      for (final f in _features(resp.data)) {
        final a = _attrs(f);
        final unitNm = _str(a, ['name']);
        insideNPS = true;
        npsName = unitNm.isNotEmpty ? unitNm : 'NPS Unit';
        break;
      }
    } catch (_) {}

    return _ProtectedLand(
      insideNPS: insideNPS,
      npsName: npsName,
      insideStatePark: false,
      stateParkName: null,
    );
  }

  // ── FAA active TFRs ────────────────────────────────────────────────────────

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
      final name = _str(_attrs(features.first), ['CALLSIGN', 'REASON', 'TYPE_CODE']);
      return _TFR(inside: true, name: name.isNotEmpty ? name : 'Active TFR');
    } on DioException catch (e) {
      final isFail = e.response?.statusCode != null ||
          e.type == DioExceptionType.connectionTimeout;
      return _TFR(inside: false, checkFailed: isFail);
    } catch (_) {
      return const _TFR(inside: false, checkFailed: true);
    }
  }

  // ── USFWS wildlife refuges (USGS National Map govunits layer 35) ──────────

  Future<_USFWS> _queryUSFWS(double lat, double lon) async {
    try {
      final resp = await _dio.get(
        'https://carto.nationalmap.gov/arcgis/rest/services/'
        'govunits/MapServer/35/query',
        queryParameters: {
          'geometry': '$lon,$lat',
          'geometryType': 'esriGeometryPoint',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'outFields': 'name',
          'returnGeometry': 'false',
          'f': 'json',
        },
      );
      final features = _features(resp.data);
      if (features.isEmpty) return const _USFWS(inside: false);
      final name = _str(_attrs(features.first), ['name']);
      return _USFWS(
          inside: true,
          name: name.isNotEmpty ? name : 'National Wildlife Refuge');
    } catch (_) {
      return const _USFWS(inside: false);
    }
  }

  // ── Status combiner ────────────────────────────────────────────────────────
  // Priority: FAA prohibited → active TFR → NPS → FAA restricted →
  //           USFWS refuge → state park → FAA controlled → clear

  _StatusResult _combineStatus(
      _FAA faa, _ProtectedLand land, _TFR tfr, _USFWS usfws) {
    final tfrNote = tfr.checkFailed
        ? '\n⚠ TFR status could not be verified — check FAA NOTAM system before flying.'
        : '';

    if (faa.hasProhibited) {
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: 'Prohibited airspace — no drone operations allowed',
        detail: _join([if (faa.names.isNotEmpty) faa.names.join(', '), tfrNote.trim()]),
      );
    }

    if (tfr.inside) {
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: 'Active TFR — no drone operations',
        detail: _join([
          tfr.name ?? 'Active TFR',
          if (land.insideNPS) 'Also inside NPS unit: ${land.npsName} (36 CFR 1.5)',
          if (land.insideStatePark) 'Also inside state park: ${land.stateParkName}',
          if (usfws.inside) 'Also in Wildlife Refuge: ${usfws.name} (permit required)',
        ]),
      );
    }

    if (land.insideNPS) {
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: '${land.npsName} — drones prohibited',
        detail: _join([
          'Prohibited under NPS regulation 36 CFR 1.5, regardless of FAA airspace class.',
          if (faa.hasRestricted) 'Also in FAA restricted airspace: ${faa.names.join(', ')}',
          if (faa.hasControlled) 'Also in controlled airspace: ${faa.names.join(', ')}',
          if (usfws.inside) 'Also in Wildlife Refuge: ${usfws.name} (permit required)',
          tfrNote.trim(),
        ]),
      );
    }

    if (faa.hasRestricted) {
      return _StatusResult(
        status: _AirspaceStatus.restricted,
        headline: 'Restricted airspace — contact the controlling agency',
        detail: _join([
          if (faa.names.isNotEmpty) faa.names.join(', '),
          if (usfws.inside) 'Also in Wildlife Refuge: ${usfws.name} (permit required)',
          if (land.insideStatePark) 'Also inside state park: ${land.stateParkName} — check state drone rules',
          tfrNote.trim(),
        ]),
      );
    }

    if (usfws.inside) {
      return _StatusResult(
        status: _AirspaceStatus.controlled,
        headline: '${usfws.name} — Special Use Permit required',
        detail: _join([
          'Drones require a USFWS Special Use Permit on national wildlife refuges. Many refuges prohibit drone use entirely — contact the refuge manager before flying.',
          if (faa.hasControlled) 'Also in controlled airspace: ${faa.names.join(', ')} (FAA auth required)',
          if (land.insideStatePark) 'Also inside state park: ${land.stateParkName} — check state drone rules',
          tfrNote.trim(),
        ]),
      );
    }

    if (land.insideStatePark) {
      return _StatusResult(
        status: _AirspaceStatus.controlled,
        headline: '${land.stateParkName} — check state park drone rules',
        detail: _join([
          'Most states prohibit drones in state parks, but rules vary. Check the specific park\'s regulations before flying.',
          if (faa.hasControlled) 'Also in controlled airspace: ${faa.names.join(', ')} (FAA auth required)',
          tfrNote.trim(),
        ]),
      );
    }

    if (faa.hasControlled) {
      return _StatusResult(
        status: _AirspaceStatus.controlled,
        headline: 'Controlled airspace — FAA authorization required',
        detail: _join([
          if (faa.names.isNotEmpty) '${faa.names.join(', ')}\nDrones require FAA authorization before flying here.'
          else 'Drones require FAA authorization before flying here.',
          tfrNote.trim(),
        ]),
      );
    }

    return _StatusResult(
      status: _AirspaceStatus.clear,
      headline: 'Class G — uncontrolled airspace',
      detail: _join([
        'No restricted airspace, national park, state park, wildlife refuge, or active TFR detected.',
        'Fly under 400 ft AGL, keep the drone in sight, and stay clear of people, vehicles, and emergency scenes.',
        tfrNote.trim(),
      ]),
    );
  }

  // ── Viewport bbox query ────────────────────────────────────────────────────

  LatLngBounds _boundsAround(double lat, double lon, double deg) =>
      LatLngBounds(LatLng(lat - deg, lon - deg), LatLng(lat + deg, lon + deg));

  Future<void> _fetchViewportZones(LatLngBounds bounds) async {
    if (!mounted) return;
    setState(() => _zonesLoading = true);

    final bbox =
        '${bounds.west},${bounds.south},${bounds.east},${bounds.north}';
    final zones = <_AirspaceZone>[];

    await Future.wait([
      // FAA Class B/C/D/E
      _bboxQuery(url: 'https://geoservices.faa.gov/arcgis/rest/services/Aeronautical/Airspace/MapServer/0/query', bbox: bbox, zoneType: 'FAA', typeFields: ['TYPE_CODE', 'LOCAL_TYPE'], nameFields: ['NAME'], out: zones),
      // FAA Special Use
      _bboxQuery(url: 'https://geoservices.faa.gov/arcgis/rest/services/Aeronautical/Airspace/MapServer/1/query', bbox: bbox, zoneType: 'FAA', typeFields: ['TYPE_CODE', 'LOCAL_TYPE'], nameFields: ['NAME'], out: zones),
      // Active TFRs
      _bboxQuery(url: 'https://geoservices.faa.gov/arcgis/rest/services/ATCSCC/TFRS/MapServer/0/query', bbox: bbox, zoneType: 'TFR', typeFields: [], nameFields: ['CALLSIGN', 'REASON'], out: zones),
      // USFWS refuges (USGS National Map govunits layer 35)
      _bboxQuery(url: 'https://carto.nationalmap.gov/arcgis/rest/services/govunits/MapServer/35/query', bbox: bbox, zoneType: 'USFWS', typeFields: [], nameFields: ['name'], out: zones),
    ]);

    if (!mounted) return;
    setState(() {
      _zones = zones;
      _zonesLoading = false;
    });
  }

  Future<void> _bboxQuery({
    required String url,
    required String bbox,
    required String zoneType,
    required List<String> typeFields,
    required List<String> nameFields,
    required List<_AirspaceZone> out,
    String? where,
  }) async {
    try {
      final allFields = {...typeFields, ...nameFields}.join(',');
      final params = <String, dynamic>{
        'geometry': bbox,
        'geometryType': 'esriGeometryEnvelope',
        'inSR': '4326',
        'spatialRel': 'esriSpatialRelIntersects',
        'outFields': allFields,
        'returnGeometry': 'true',
        'outSR': '4326',
        'simplifyTolerance': '0.003',
        'resultRecordCount': '100',
        'f': 'json',
      };
      if (where != null) params['where'] = where;

      final resp = await _dio.get(url, queryParameters: params);

      for (final f in _features(resp.data)) {
        final a = _attrs(f);
        final type = typeFields.isNotEmpty
            ? _str(a, typeFields).let((t) => t.isNotEmpty ? t : zoneType)
            : zoneType;
        final name =
            _str(a, nameFields).let((n) => n.isNotEmpty ? n : zoneType);
        final geom = f['geometry'] as Map<String, dynamic>?;
        for (final ring in ((geom?['rings'] as List?) ?? []).take(4)) {
          final pts = <LatLng>[];
          for (final raw in (ring as List).take(500)) {
            final c = raw as List;
            if (c.length >= 2) {
              pts.add(LatLng(
                  (c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
          if (pts.length >= 3) out.add(_AirspaceZone(name, type, pts));
        }
      }
    } catch (_) {}
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    // Toggle the recenter button when the GPS pin drifts off-centre. setState
    // only on a flip so we don't rebuild every pan frame.
    if (_lat != null && _lon != null) {
      final off = MapRecenterButton.offCenter(camera, LatLng(_lat!, _lon!));
      if (off != _showRecenter) setState(() => _showRecenter = off);
    }
    // Refresh airspace zones for the new viewport once panning settles. The
    // status card stays put — it used to slide away on every pan and back 700ms
    // later, which read as the card bouncing up and down.
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

  String? _join(List<String> parts) {
    final s = parts.where((p) => p.isNotEmpty).join('\n');
    return s.isEmpty ? null : s;
  }

  // ── Zone colors ───────────────────────────────────────────────────────────
  // Draw order (bottom to top): STATE_PARK → USFWS → NPS → FAA → TFR

  Color _zoneFill(String type) {
    if (type == 'TFR')        return const Color(0x44FFB800);
    if (type == 'USFWS')      return const Color(0x2D9B30FF);
    if (type == 'NPS')        return const Color(0x2D1B7F00);
    if (type == 'STATE_PARK') return const Color(0x2D009688);
    if (type.startsWith('P')) return const Color(0x55DD0000);
    if (type.startsWith('R')) return const Color(0x3DDD0000);
    if (type.startsWith('W') || type.startsWith('A')) return Colors.orange.withValues(alpha: 0.22);
    if (type.contains('B'))   return const Color(0x330070C0);
    if (type.contains('C'))   return const Color(0x33AA00FF);
    if (type.contains('D'))   return const Color(0x220070C0);
    return Colors.orange.withValues(alpha: 0.14);
  }

  Color _zoneBorder(String type) {
    if (type == 'TFR')        return const Color(0xFFFFB800);
    if (type == 'USFWS')      return const Color(0xFF7B10EE);
    if (type == 'NPS')        return const Color(0xFF1B7F00);
    if (type == 'STATE_PARK') return const Color(0xFF00695C);
    if (type.startsWith('P') || type.startsWith('R')) return const Color(0xFFCC2200);
    if (type.startsWith('W') || type.startsWith('A')) return Colors.orange;
    if (type.contains('B'))   return const Color(0xFF0070C0);
    if (type.contains('C'))   return const Color(0xFFAA00FF);
    if (type.contains('D'))   return const Color(0xFF0070C0);
    return Colors.orange;
  }

  double _zoneBorderWidth(String type) =>
      const {'NPS', 'USFWS', 'STATE_PARK'}.contains(type) ? 1.5 : 2.0;

  static const _landTypes = {'NPS', 'TFR', 'USFWS', 'STATE_PARK'};

  List<_AirspaceZone> _zonesOfType(String type) =>
      _zones.where((z) => z.type == type && z.ring.length >= 3).toList();
  List<_AirspaceZone> _faaZones() =>
      _zones.where((z) => !_landTypes.contains(z.type) && z.ring.length >= 3).toList();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lat = _lat ?? 29.5;
    final lon = _lon ?? -90.0;

    final usfwsZ = _zonesOfType('USFWS');
    // NPS overlay uses pre-loaded static asset — visible regardless of pan/zoom,
    // no API call needed, works instantly and offline.
    final npsZ   = _staticNpsZones.where((z) => z.ring.length >= 3).toList();
    final faaZ   = _faaZones();
    final tfrZ   = _zonesOfType('TFR');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavy,
        leading: const BackButton(color: Colors.white),
        title: const Text('Before You Fly',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    'https://services.arcgisonline.com/ArcGIS/rest/services/'
                    'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.mattbettinger.tides',
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
                        boxShadow: [BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.50),
                            blurRadius: 8)],
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
                    child: const Icon(Icons.location_on, color: kCyan,
                        size: 36,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                  ),
                ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© Esri'),
                  TextSourceAttribution('FAA · USGS National Map · USFWS'),
                ],
              ),
            ],
          ),
          if (_tappedPoint == null && _gpsStatus != _AirspaceStatus.loading)
            Positioned(
              top: 12, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          // Only while the card is collapsed — when expanded it covers the
          // lower map and carries its own "My Location" action.
          MapRecenterButton(
            visible: _showRecenter && _cardCollapsed && _lat != null,
            bottom: 96,
            onPressed: () {
              if (_lat != null && _lon != null) {
                _mapController.move(LatLng(_lat!, _lon!), 11.0);
                setState(() => _showRecenter = false);
              }
            },
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _cardCollapsed
                ? _CollapsedBar(
                    status: _displayStatus,
                    headline: _displayHeadline,
                    onExpand: () => setState(() => _cardCollapsed = false),
                  )
                : _StatusCard(
                    status: _displayStatus,
                    headline: _displayHeadline,
                    detail: _displayDetail,
                    isTappedLocation: _tappedPoint != null,
                    onRetry: _load,
                    onClearTap: _clearTap,
                    onCollapse: () => setState(() => _cardCollapsed = true),
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
  const _FAA({required this.hasProhibited, required this.hasRestricted,
      required this.hasControlled, required this.names});
}

class _ProtectedLand {
  final bool insideNPS;
  final String? npsName;
  final bool insideStatePark;
  final String? stateParkName;
  const _ProtectedLand({
    required this.insideNPS,
    this.npsName,
    required this.insideStatePark,
    this.stateParkName,
  });
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
  final VoidCallback onCollapse;

  const _StatusCard({
    required this.status,
    required this.headline,
    this.detail,
    required this.isTappedLocation,
    required this.onRetry,
    required this.onClearTap,
    required this.onCollapse,
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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
            // Tap (or drag down on) the handle to collapse the card to a thin bar.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCollapse,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 0) onCollapse();
              },
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        color: Colors.white38, size: 18),
                  ],
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: const [
                _LegendChip(color: Color(0x55DD0000), border: Color(0xFFCC2200), label: 'Prohibited'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x3DDD0000), border: Color(0xFFCC2200), label: 'Restricted'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x44FFB800), border: Color(0xFFFFB800), label: 'Active TFR'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x44FF8C00), border: Colors.orange,    label: 'Warning'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x330070C0), border: Color(0xFF0070C0), label: 'Class B/C/D'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x2D1B7F00), border: Color(0xFF1B7F00), label: 'Nat\'l Park'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x2D009688), border: Color(0xFF00695C), label: 'State Park'),
                SizedBox(width: 5),
                _LegendChip(color: Color(0x2D9B30FF), border: Color(0xFF7B10EE), label: 'Wildlife Refuge'),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(isTappedLocation ? Icons.place : Icons.my_location,
                  size: 13,
                  color: isTappedLocation ? kCyan : Colors.blue),
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
                      child: CircularProgressIndicator(
                          color: kCyan, strokeWidth: 2),
                    ),
                  )
                else
                  Icon(statusIcon, color: textColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(headline,
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
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
                      side: BorderSide(
                          color: Colors.blue[300]!.withValues(alpha: 0.6)),
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
              'Data: FAA airspace · FAA TFRs · USGS National Map (NPS units) · USFWS refuges. '
              'For reference only — always confirm before flying.',
              style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// The collapsed form of [_StatusCard]: a thin bar pinned to the bottom that
/// still shows the airspace status colour + headline at a glance. Tapping it (or
/// dragging up) re-expands the full card. Collapse/expand is entirely
/// user-driven — nothing here reacts to map panning, so it can never bounce.
class _CollapsedBar extends StatelessWidget {
  final _AirspaceStatus status;
  final String headline;
  final VoidCallback onExpand;

  const _CollapsedBar({
    required this.status,
    required this.headline,
    required this.onExpand,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onExpand,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < 0) onExpand();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: BoxDecoration(
              color: kNavyLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: borderColor.withValues(alpha: 0.65), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.expand_less, color: Colors.white38, size: 18),
                Row(
                  children: [
                    Icon(statusIcon, color: textColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Tap to expand',
                        style:
                            TextStyle(color: Colors.white30, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final Color border;
  final String label;
  const _LegendChip(
      {required this.color, required this.border, required this.label});

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
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      );
}
