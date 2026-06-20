import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/units_provider.dart';
import '../theme.dart';
import '../widgets/map_recenter_button.dart';

// ── Water Temp map ────────────────────────────────────────────────────────────
//
// Three ocean layers rendered straight from NOAA CoastWatch ERDDAP
// (coastwatch.pfeg.noaa.gov — free, no key; the coastwatch.noaa.gov mirror
// has been unreliable):
//
//   Water Temp — JPL MUR 1km daily sea-surface temperature (analysed_sst)
//   Upwelling  — MUR daily SST *anomaly* vs normal (sstAnom); blue = colder
//                than normal = upwelling signal
//   Turbidity  — MODIS Kd490 8-day composite (k490); the daily product is too
//                cloud-gappy to be useful
//
// Each layer is one server-rendered `.transparentPng` (land transparent)
// covering the visible bounds + margin, pinned on the map via OverlayImage —
// the same composited-PNG technique as the wind screen's radar layer, without
// the timeline. The PNG is EPSG:4326 on a Web-Mercator map, which stretches
// N–S slightly; spans are clamped (≤8° lat) to keep that imperceptible.

enum _Layer { sst, anomaly, turbidity }

class _LayerDef {
  final String label;
  final IconData icon;
  final String dataset;
  final String variable;
  final String palette;
  final String ageNote; // how fresh "(last)" actually is
  // Coarse grids (4km MODIS) render as visible blocks: request the PNG near
  // the data's native cell size and gaussian-blur it on screen instead.
  final double? smoothCellDeg;
  const _LayerDef({
    required this.label,
    required this.icon,
    required this.dataset,
    required this.variable,
    required this.palette,
    required this.ageNote,
    this.smoothCellDeg,
  });
}

const _kLayers = {
  _Layer.sst: _LayerDef(
    label: 'Water Temp',
    icon: Icons.thermostat,
    dataset: 'jplMURSST41',
    variable: 'analysed_sst',
    palette: 'Rainbow2',
    ageNote: 'JPL MUR daily · 1–2 day lag',
  ),
  _Layer.anomaly: _LayerDef(
    label: 'Upwelling',
    icon: Icons.waves,
    dataset: 'jplMURSST41anom1day',
    variable: 'sstAnom',
    palette: 'BlueWhiteRed',
    ageNote: 'MUR anomaly daily · 1–2 day lag',
  ),
  _Layer.turbidity: _LayerDef(
    label: 'Turbidity',
    icon: Icons.blur_on,
    dataset: 'erdMH1kd4908day',
    variable: 'k490',
    palette: 'Rainbow2',
    ageNote: 'MODIS 8-day composite · gaps = clouds',
    smoothCellDeg: 1 / 24, // MODIS Kd490 grid is ~4km (0.0417°)
  ),
};

// ── Prefetch ──────────────────────────────────────────────────────────────────
// Warms the default SST overlay before the screen opens (called on map-icon
// tap in detail_screen, same pattern as prefetchWindMap). Stores the result
// in _prefetchCache so initState can paint it immediately, skipping the
// loading spinner on first open.

(double, double) _sstRangeFor(double lat) {
  final a = lat.abs();
  if (a > 45) return (4, 20);
  if (a > 35) return (10, 26);
  return (15, 33);
}

final _prefetchCache = <String, (String, LatLngBounds)>{};

void prefetchWaterTempMap(double lat, double lon, BuildContext context) {
  final key = '${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}';
  if (_prefetchCache.containsKey(key)) return;
  // Approximate zoom-7 view (~6° lat × 8° lon), same 0.5° rounding as
  // _requestBounds — URL may hit Flutter's image cache exactly on open.
  double down(double v) => (v * 2).floorToDouble() / 2;
  double up(double v) => (v * 2).ceilToDouble() / 2;
  final s = down(lat - 3.0).clamp(-89.5, 89.5);
  final n = up(lat + 3.0).clamp(-89.5, 89.5);
  final w = down(lon - 4.0);
  final e = up(lon + 4.0);
  final (lo, hi) = _sstRangeFor(lat);
  final h = ((n - s) / (e - w) * 512).round().clamp(64, 768);
  final url = 'https://coastwatch.pfeg.noaa.gov/erddap/griddap/'
      'jplMURSST41.transparentPng'
      '?analysed_sst%5B(last)%5D%5B($s):($n)%5D%5B($w):($e)%5D'
      '&.draw=surface'
      '&.vars=longitude%7Clatitude%7Canalysed_sst'
      '&.colorBar=Rainbow2%7C%7C%7C$lo%7C$hi%7C'
      '&.size=512%7C$h';
  final bounds = LatLngBounds(LatLng(s, w), LatLng(n, e));
  precacheImage(NetworkImage(url), context)
      .then((_) => _prefetchCache[key] = (url, bounds))
      .catchError((_) {});
}

class WaterTempMapScreen extends ConsumerStatefulWidget {
  final double lat;
  final double lon;
  final String stationName;
  const WaterTempMapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.stationName,
  });

  @override
  ConsumerState<WaterTempMapScreen> createState() =>
      _WaterTempMapScreenState();
}

class _WaterTempMapScreenState extends ConsumerState<WaterTempMapScreen> {
  final _mapController = MapController();
  Timer? _moveDebounce;

  _Layer _currentLayer = _Layer.sst;
  String? _overlayUrl; // currently displayed (pre-cached) overlay
  LatLngBounds? _overlayBounds;
  bool _loading = true; // nothing on screen yet for this layer
  bool _refreshing = false; // pan/zoom refetch with old overlay still up
  String? _error;

  // Per-session overlay cache: switching back to a visited layer is instant.
  final _layerCache = <_Layer, (String, LatLngBounds)>{};

  // Blur filter is stateless; creating it once avoids per-rebuild allocation.
  static final _kBlurFilter =
      ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3, tileMode: ui.TileMode.decal);

  // ── Tap probe ──
  // The overlay is a server-rendered PNG (no client-side grid), so a tap
  // reads the value by asking ERDDAP for that single grid cell as JSON.
  static final _probeDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  LatLng? _probePoint;
  bool _probeLoading = false;
  String? _probeText;
  int _probeSeq = 0; // ignore stale responses after a newer tap

  // Recenter button shows once the station pin pans off-centre. The pin stays
  // anchored; this just snaps the camera back. Toggled only by panning.
  bool _showRecenter = false;

  // erdMH1 latitude storage order isn't documented like MUR's (ascending,
  // verified); learned empirically — flipped once if the first request 500s.
  static bool _kd490LatAscending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // If prefetchWaterTempMap warmed the SST overlay before this screen
      // opened, paint it immediately — no loading spinner on first open.
      final key =
          '${widget.lat.toStringAsFixed(1)}_${widget.lon.toStringAsFixed(1)}';
      final pre = _prefetchCache.remove(key);
      if (pre != null) {
        _layerCache[_Layer.sst] = pre;
        setState(() {
          _overlayUrl = pre.$1;
          _overlayBounds = pre.$2;
          _loading = false;
        });
      }
      // Either confirms the prefetched URL (early-return) or silently updates
      // to the exact screen bounds in the background (_refreshing path).
      _fetchOverlay();
    });
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    super.dispose();
  }

  // SST color range tuned to the station's latitude band.
  (double, double) _sstRange() => _sstRangeFor(widget.lat);

  (double, double) _rangeFor(_Layer l) => switch (l) {
        _Layer.sst => _sstRange(),
        _Layer.anomaly => (-5, 5),
        // Min sits below the data floor (Kd490 ≥ ~0.02) so Rainbow2's purple
        // band falls out of range and the clearest water renders BLUE — blue
        // = clear reads naturally; purple = clear confused people.
        _Layer.turbidity => (-0.5, 2),
      };

  // Re-fetch when the user pans/zooms so the overlay follows the map.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    final off =
        MapRecenterButton.offCenter(camera, LatLng(widget.lat, widget.lon));
    if (off != _showRecenter) setState(() => _showRecenter = off);
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      // Skip if the current overlay already covers the new request area —
      // no API chatter for small pans within the already-loaded region.
      if (_overlayBounds != null) {
        final nb = _requestBounds();
        if (_overlayBounds!.north >= nb.north &&
            _overlayBounds!.south <= nb.south &&
            _overlayBounds!.east >= nb.east &&
            _overlayBounds!.west <= nb.west) return;
      }
      _fetchOverlay();
    });
  }

  // Visible bounds + 25% margin, edges rounded OUTWARD to 0.5° so nearby
  // pans/zooms reproduce the identical URL (= Flutter image-cache hit, no
  // network), span clamped to keep ERDDAP render time and the 4326-on-Mercator
  // stretch bounded.
  LatLngBounds _requestBounds() {
    final b = _mapController.camera.visibleBounds;
    const margin = 0.25;
    final latSpan = b.north - b.south;
    final lonSpan = b.east - b.west;
    var south = b.south - latSpan * margin;
    var north = b.north + latSpan * margin;
    var west = b.west - lonSpan * margin;
    var east = b.east + lonSpan * margin;

    // Clamp spans (centered) before rounding.
    final latC = (north + south) / 2;
    final lonC = (east + west) / 2;
    if (north - south > 8) {
      south = latC - 4;
      north = latC + 4;
    }
    if (east - west > 10) {
      west = lonC - 5;
      east = lonC + 5;
    }

    double down(double v) => (v * 2).floorToDouble() / 2;
    double up(double v) => (v * 2).ceilToDouble() / 2;
    return LatLngBounds(
      LatLng(down(south).clamp(-89.5, 89.5), down(west)),
      LatLng(up(north).clamp(-89.5, 89.5), up(east)),
    );
  }

  String _urlFor(_Layer l, LatLngBounds b, {required bool latAscending}) {
    final def = _kLayers[l]!;
    final (lo, hi) = _rangeFor(l);
    final latA = latAscending ? b.south : b.north;
    final latB = latAscending ? b.north : b.south;
    // PNG aspect must match the bounds it's pinned on or the data shifts.
    // For coarse grids, ~1 pixel per data cell: ERDDAP draws cells as hard
    // blocks, so a near-native render + the on-screen blur upscales into a
    // smooth gradient instead of chunky 4km squares.
    final w = def.smoothCellDeg != null
        ? ((b.east - b.west) / def.smoothCellDeg!).round().clamp(96, 512)
        : 512;
    final h = ((b.north - b.south) / (b.east - b.west) * w)
        .round()
        .clamp(64, 768);
    return 'https://coastwatch.pfeg.noaa.gov/erddap/griddap/'
        '${def.dataset}.transparentPng'
        '?${def.variable}%5B(last)%5D%5B($latA):($latB)%5D%5B(${b.west}):(${b.east})%5D'
        '&.draw=surface'
        '&.vars=longitude%7Clatitude%7C${def.variable}'
        '&.colorBar=${def.palette}%7C%7C%7C$lo%7C$hi%7C'
        '&.size=$w%7C$h';
  }

  Future<void> _fetchOverlay({_Layer? layer}) async {
    final l = layer ?? _currentLayer;
    final bounds = _requestBounds();
    var ascending = l == _Layer.turbidity ? _kd490LatAscending : true;
    var url = _urlFor(l, bounds, latAscending: ascending);
    if (url == _overlayUrl && l == _currentLayer) return; // same view

    setState(() {
      if (_overlayUrl == null) {
        _loading = true;
      } else {
        _refreshing = true; // keep the old overlay up while the new one loads
      }
      _error = null;
    });

    try {
      try {
        await precacheImage(NetworkImage(url), context)
            .timeout(const Duration(seconds: 25));
      } catch (e) {
        if (l != _Layer.turbidity || !mounted) rethrow;
        // Unknown lat order — try the flipped request once and remember.
        ascending = !ascending;
        url = _urlFor(l, bounds, latAscending: ascending);
        await precacheImage(NetworkImage(url), context)
            .timeout(const Duration(seconds: 25));
        _kd490LatAscending = ascending;
      }
      if (!mounted) return;
      _layerCache[l] = (url, bounds);
      setState(() {
        _overlayUrl = url;
        _overlayBounds = bounds;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        // Only block the screen when there's nothing to look at.
        if (_overlayUrl == null) {
          _error = 'NOAA CoastWatch is temporarily down —\n'
              'try again in a few minutes.';
        }
      });
    }
  }

  void _setLayer(_Layer l) {
    if (l == _currentLayer) return;
    final cached = _layerCache[l];
    setState(() {
      _currentLayer = l;
      if (cached != null) {
        // Instant repaint from session cache; _fetchOverlay will confirm or
        // silently update if the view has moved since we last visited.
        _overlayUrl = cached.$1;
        _overlayBounds = cached.$2;
      } else {
        _overlayUrl = null;
        _overlayBounds = null;
      }
      _clearProbe();
    });
    _fetchOverlay(layer: l);
  }

  // ── Tap probe ────────────────────────────────────────────────────────────

  void _clearProbe() {
    _probeSeq++;
    _probePoint = null;
    _probeLoading = false;
    _probeText = null;
  }

  Future<void> _probe(LatLng p) async {
    final l = _currentLayer;
    final def = _kLayers[l]!;
    final seq = ++_probeSeq;
    setState(() {
      _probePoint = p;
      _probeLoading = true;
      _probeText = null;
    });

    final lat = p.latitude.toStringAsFixed(3);
    final lon = p.longitude.toStringAsFixed(3);
    // Same single-cell request for both lat/lon ends: ERDDAP snaps "(value)"
    // to the nearest grid index, so this returns exactly one row.
    final url = 'https://coastwatch.pfeg.noaa.gov/erddap/griddap/'
        '${def.dataset}.json'
        '?${def.variable}%5B(last)%5D%5B($lat):($lat)%5D%5B($lon):($lon)%5D';

    String text;
    try {
      final resp = await _probeDio.get(url);
      final data = resp.data is String
          ? null // ERDDAP errors come back as HTML strings
          : resp.data as Map<String, dynamic>;
      final rows = (data?['table']?['rows'] as List?) ?? const [];
      final v = rows.isEmpty ? null : (rows.first as List).last as num?;
      text = v == null
          ? 'No data at this spot — land, or a cloud gap'
          : _formatProbe(l, v.toDouble());
    } catch (_) {
      text = 'Couldn’t read this point — NOAA may be busy, try again';
    }
    if (!mounted || seq != _probeSeq) return; // superseded by a newer tap
    setState(() {
      _probeLoading = false;
      _probeText = text;
    });
  }

  String _formatProbe(_Layer l, double v) {
    final metric = ref.read(unitsProvider);
    final unit = metric ? '°C' : '°F';
    // Absolute temperature: °F needs the +32 offset.
    String temp(double c) =>
        '${(metric ? c : c * 9 / 5 + 32).toStringAsFixed(1)}$unit';
    // Temperature *difference* (anomaly): scale only, no offset.
    String delta(double c) {
      final val = metric ? c : c * 9 / 5;
      return '${val > 0 ? '+' : ''}${val.toStringAsFixed(1)}$unit';
    }

    switch (l) {
      case _Layer.sst:
        // analysed_sst is °C; for anglers this *is* the water temperature.
        return 'Water temp ${temp(v)}';
      case _Layer.anomaly:
        final note = v <= -1.5
            ? '  ·  upwelling signal'
            : v >= 1.5
                ? '  ·  warmer than normal'
                : '  ·  near normal';
        return '${delta(v)} vs normal$note';
      case _Layer.turbidity:
        // Kd490 (m⁻¹) = how fast blue-green light dims with depth.
        // 1/Kd490 ≈ the depth sunlight effectively reaches.
        final desc = v < 0.15
            ? 'clear'
            : v < 0.4
                ? 'slightly stained'
                : v < 1.0
                    ? 'murky'
                    : 'very murky';
        final depthM = 1 / v.clamp(0.02, 10);
        final depth = metric
            ? '${depthM.toStringAsFixed(depthM >= 10 ? 0 : 1)} m'
            : '${(depthM * 3.281).toStringAsFixed(0)} ft';
        return 'Clarity: $desc  ·  sunlight to ~$depth  ·  Kd490 ${v.toStringAsFixed(2)}';
    }
  }

  void _showLayerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LayerPicker(
        current: _currentLayer,
        onSelect: (l) {
          Navigator.pop(context);
          _setLayer(l);
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
            onPressed: () {
              _overlayUrl = null; // force a refetch of the current view
              _fetchOverlay();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.lat, widget.lon),
              // ~5° of latitude in view: wide enough to see the temperature
              // structure, tight enough that the 4326 overlay stays true.
              initialZoom: 7,
              minZoom: 5,
              maxZoom: 10,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation |
                    InteractiveFlag.pinchMove |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
              onPositionChanged: _onPositionChanged,
              onTap: (_, p) => _probe(p),
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
              if (_overlayUrl != null && _overlayBounds != null)
                _smoothed(
                  def,
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: _overlayBounds!,
                        imageProvider: NetworkImage(_overlayUrl!),
                        // Basemap coastline/labels read through the wash.
                        opacity: 0.75,
                      ),
                    ],
                  ),
                ),
              MarkerLayer(markers: [
                Marker(
                  point: LatLng(widget.lat, widget.lon),
                  width: 36,
                  height: 44,
                  alignment: Alignment.bottomCenter,
                  child: const Icon(
                    Icons.location_on,
                    size: 36,
                    color: kCyan,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 6),
                      Shadow(color: Colors.white, blurRadius: 2),
                    ],
                  ),
                ),
                if (_probePoint != null)
                  Marker(
                    point: _probePoint!,
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
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© CARTO'),
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('NOAA CoastWatch · JPL MUR · MODIS'),
                ],
              ),
            ],
          ),
          // Data-age chip — "(last)" is the freshest grid, not "right now".
          if (!_loading && _error == null)
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_refreshing) ...[
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                              color: kCyan, strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(def.ageNote,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          // Tap hint — visible until the user taps for the first time.
          if (_probePoint == null && _overlayUrl != null &&
              !_loading && _error == null)
            Positioned(
              top: 46,
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
          // Probe reading — tap anywhere on the water to populate.
          if (_probePoint != null && !_loading && _error == null)
            Positioned(
              top: 46,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(_clearProbe),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kCyan, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_probeLoading) ...[
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                color: kCyan, strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          const Text('Reading…',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ] else ...[
                          Flexible(
                            child: Text(_probeText ?? '',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.close,
                              color: Colors.white38, size: 13),
                        ],
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
                    const SizedBox(height: 4),
                    const Text('NOAA renders this on demand — a few seconds',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 11)),
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
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _fetchOverlay(),
                    child: const Text('Retry', style: TextStyle(color: kCyan)),
                  ),
                ],
              ),
            ),
          if (!_loading && _error == null) _legend(def, metric),
          MapRecenterButton(
            visible: _showRecenter,
            bottom: 104,
            onPressed: () {
              _mapController.move(LatLng(widget.lat, widget.lon), 7);
              setState(() => _showRecenter = false);
            },
          ),
        ],
      ),
    );
  }

  // Gaussian-blur coarse-grid layers so 4km cells melt into a smooth wash;
  // decal tile mode keeps the blur from smearing past transparent edges.
  Widget _smoothed(_LayerDef def, Widget child) => def.smoothCellDeg == null
      ? child
      : ImageFiltered(imageFilter: _kBlurFilter, child: child);

  // ── Legend ──────────────────────────────────────────────────────────────────
  //
  // Chip colors approximate the ERDDAP palettes (Rainbow2 cold→hot,
  // BlueWhiteRed diverging) at the labelled values.

  List<(Color, String)> _legendItems(bool metric) {
    String temp(double c) =>
        metric ? '${c.round()}°C' : '${(c * 9 / 5 + 32).round()}°F';
    switch (_currentLayer) {
      case _Layer.sst:
        final (lo, hi) = _sstRange();
        final third = (hi - lo) / 3;
        return [
          (const Color(0xFF8E44AD), '≤${temp(lo)}'),
          (const Color(0xFF29B6D8), temp(lo + third)),
          (const Color(0xFFE8C233), temp(lo + 2 * third)),
          (const Color(0xFFD83A2E), '≥${temp(hi)}'),
        ];
      case _Layer.anomaly:
        final d = metric ? '5°C' : '9°F';
        return [
          (const Color(0xFF2D5FD0), '$d colder — upwelling'),
          (Colors.white, 'normal for this date'),
          (const Color(0xFFD0402D), '$d warmer than normal'),
        ];
      case _Layer.turbidity:
        // Labels carry the approximate depth sunlight reaches (≈1/Kd490) at
        // that band, so the colors translate to something castable.
        return metric
            ? [
                (const Color(0xFF2D6FE0), 'Clear · sun 10+ m'),
                (const Color(0xFF35C6DC), 'Stained · ~2 m'),
                (const Color(0xFFE8C233), 'Murky · ~1 m'),
                (const Color(0xFFD83A2E), 'Very murky · <½ m'),
              ]
            : [
                (const Color(0xFF2D6FE0), 'Clear · sun 30+ ft'),
                (const Color(0xFF35C6DC), 'Stained · ~7 ft'),
                (const Color(0xFFE8C233), 'Murky · ~3 ft'),
                (const Color(0xFFD83A2E), 'Very murky · <2 ft'),
              ];
    }
  }

  Widget _legend(_LayerDef def, bool metric) => Positioned(
        // Lift above the system navigation/gesture bar so it isn't clipped.
        bottom: 32 + MediaQuery.of(context).viewPadding.bottom,
        left: 12,
        right: 12,
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                // Wrap, not Row: the descriptive labels overflow a Row on
                // narrow phones; wrapping to a second line is fine.
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: _legendItems(metric)
                      .expand((item) => [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: Container(
                                width: 8,
                                height: 8,
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
                          ])
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      );
}

// ── Layer picker (bottom sheet) ──────────────────────────────────────────────

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
              width: 36,
              height: 4,
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
                child: Text('OCEAN LAYER',
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
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal)),
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
