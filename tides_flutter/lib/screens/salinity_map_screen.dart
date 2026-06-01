import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

// NOAA NGOFS2 (Northern Gulf of America Operational Forecast System) renders
// hourly surface-salinity map plots as PNGs on its CDN. There is no salinity
// data grid we can sample on mobile any more (the old ArcGIS nowCOAST raster
// was decommissioned), but these pre-rendered forecast frames cover exactly the
// inshore bays that matter for fishing — so we loop them like the rain radar.
//
//   Option (frame list): {cdn}/NGOFS2_{code}_all_sa_fore_option
//   Each line:  <option value="model_graphics/NGOFS2_gb_all_sa_fore_<ts>.png">1000 (CDT) 05/30/26
//   Frame image: {cdn}/NGOFS2_gb_all_sa_fore_<ts>.png   (the model_graphics/ prefix is dropped)

const _cdn =
    'https://cdn.tidesandcurrents.noaa.gov/ofs/ngofs2/wwwgraphics';

class _SalRegion {
  final String code;   // option-file subdomain code
  final String label;  // human name
  final double lat, lon;
  const _SalRegion(this.code, this.label, this.lat, this.lon);
}

// NGOFS2 salinity subdomains, with approximate centers used to auto-pick the
// region nearest the station. `gom` is the whole-Gulf overview.
const _kRegions = <_SalRegion>[
  _SalRegion('gb', 'Galveston Bay',          29.4, -94.9),
  _SalRegion('ma', 'Matagorda Bay',          28.5, -96.2),
  _SalRegion('cc', 'Corpus Christi',         27.8, -97.1),
  _SalRegion('sn', 'Sabine–Neches',          29.7, -93.9),
  _SalRegion('lc', 'Calcasieu / Lake Charles', 29.9, -93.3),
  _SalRegion('lp', 'Lake Pontchartrain',     30.1, -90.1),
  _SalRegion('gf', 'Gulfport',               30.3, -89.1),
  _SalRegion('pg', 'Pascagoula',             30.3, -88.5),
  _SalRegion('mb', 'Mobile Bay',             30.4, -88.0),
  _SalRegion('gom', 'Gulf of America (overview)', 27.5, -90.5),
];

class _SalFrame {
  final String url;
  final String label; // e.g. "10:00 CDT · 05/30"
  const _SalFrame(this.url, this.label);
}

class SalinityMapScreen extends StatefulWidget {
  final double lat;
  final double lon;
  final String stationName;

  const SalinityMapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.stationName,
  });

  @override
  State<SalinityMapScreen> createState() => _SalinityMapScreenState();
}

class _SalinityMapScreenState extends State<SalinityMapScreen> {
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {
      // The CDN rejects requests without a browser-like UA.
      'User-Agent':
          'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 Tides/2.3',
    },
  ));

  late _SalRegion _region;
  List<_SalFrame> _frames = [];
  int _index = 0;
  bool _playing = true;
  bool _loading = true;
  String? _error;
  bool _outOfCoverage = false;
  Timer? _anim;

  @override
  void initState() {
    super.initState();
    final (region, dist) = _nearestRegion(widget.lat, widget.lon);
    _region = region;
    // NGOFS2 only models the northern Gulf of America. If the station is far
    // from every modeled bay (e.g. East/West coast, Hawaii), don't show a
    // misleading out-of-area map — offer to browse Gulf regions instead.
    if (dist > 4.0) {
      _outOfCoverage = true;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _anim?.cancel();
    super.dispose();
  }

  (_SalRegion, double) _nearestRegion(double lat, double lon) {
    // The Gulf overview center is far offshore — exclude it from auto-pick so a
    // coastal station always lands on its local bay.
    _SalRegion best = _kRegions.first;
    double bestD = double.infinity;
    for (final r in _kRegions) {
      if (r.code == 'gom') continue;
      final dLat = r.lat - lat;
      final dLon = r.lon - lon;
      final d = dLat * dLat + dLon * dLon;
      if (d < bestD) {
        bestD = d;
        best = r;
      }
    }
    return (best, math.sqrt(bestD));
  }

  Future<void> _load() async {
    _anim?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _frames = [];
      _index = 0;
    });
    try {
      final resp = await _dio.get<String>(
        '$_cdn/NGOFS2_${_region.code}_all_sa_fore_option',
        options: Options(responseType: ResponseType.plain),
      );
      final frames = _parseOption(resp.data ?? '');
      if (frames.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No salinity forecast for this region right now';
            _loading = false;
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _frames = frames;
        _index = 0;
        _loading = false;
      });
      _precache();
      if (_playing) _startAnim();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load salinity map';
          _loading = false;
        });
      }
    }
  }

  List<_SalFrame> _parseOption(String body) {
    final re = RegExp(
        r'value="(?:model_graphics/)?([^"]+\.png)"[^>]*>([^<\r\n]+)');
    final out = <_SalFrame>[];
    for (final m in re.allMatches(body)) {
      final file = m.group(1)!.split('/').last;
      out.add(_SalFrame('$_cdn/$file', _fmtLabel(m.group(2)!.trim())));
    }
    return out;
  }

  // "1000 (CDT) 05/30/26" -> "10:00 CDT · 05/30"
  String _fmtLabel(String raw) {
    final m = RegExp(r'^(\d{2})(\d{2})\s*\(([^)]+)\)\s*(\d{2})/(\d{2})')
        .firstMatch(raw);
    if (m == null) return raw;
    return '${m[1]}:${m[2]} ${m[3]} · ${m[4]}/${m[5]}';
  }

  void _precache() {
    for (final f in _frames) {
      precacheImage(NetworkImage(f.url), context).catchError((_) {});
    }
  }

  void _startAnim() {
    _anim?.cancel();
    if (_frames.length < 2) return;
    void schedule() {
      final atEnd = _index >= _frames.length - 1;
      _anim = Timer(Duration(milliseconds: atEnd ? 1400 : 550), () {
        if (!mounted || !_playing) return;
        setState(() => _index = atEnd ? 0 : _index + 1);
        schedule();
      });
    }
    schedule();
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      if (_index >= _frames.length - 1) _index = 0;
      _startAnim();
    } else {
      _anim?.cancel();
    }
  }

  void _showRegionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                child: Text('SALINITY REGION',
                    style: TextStyle(
                        color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _kRegions.map((r) {
                  final selected = r.code == _region.code;
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place,
                        color: selected ? kCyan : Colors.white54, size: 20),
                    title: Text(r.label,
                        style: TextStyle(
                            color: selected ? kCyan : Colors.white,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    trailing: selected
                        ? const Icon(Icons.check, color: kCyan, size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (r.code != _region.code || _outOfCoverage) {
                        setState(() {
                          _region = r;
                          _outOfCoverage = false;
                        });
                        _load();
                      }
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: kNavyLight,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.stationName.toUpperCase()} — SALINITY',
          style: const TextStyle(color: kCyan, fontSize: 13),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.place, color: kCyan),
            tooltip: 'Change region',
            onPressed: _showRegionPicker,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: kCyan),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _outOfCoverage
                ? _coverageView()
                : _error != null
                ? _errorView()
                : _frames.isEmpty
                    ? const SizedBox()
                    : InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Center(
                          child: Image.network(
                            _frames[_index].url,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            loadingBuilder: (c, child, prog) =>
                                prog == null ? child : const SizedBox(),
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                color: Colors.white24,
                                size: 48),
                          ),
                        ),
                      ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: kCyan),
                    SizedBox(height: 12),
                    Text('Loading salinity forecast…',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null && _frames.isNotEmpty) _regionChip(),
          if (!_loading && _error == null && _frames.length > 1) _timeline(),
        ],
      ),
    );
  }

  Widget _coverageView() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.water_drop_outlined,
                  color: Colors.white24, size: 48),
              const SizedBox(height: 14),
              const Text(
                'Salinity forecast covers Gulf of America bays',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                "NOAA's NGOFS2 model doesn't reach this station's area. "
                'You can still browse the Gulf bay maps.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: _showRegionPicker,
                icon: const Icon(Icons.place, color: kCyan, size: 18),
                label: const Text('Browse Gulf regions',
                    style: TextStyle(color: kCyan)),
              ),
            ],
          ),
        ),
      );

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.white38, size: 40),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: const Text('Retry', style: TextStyle(color: kCyan)),
            ),
          ],
        ),
      );

  Widget _regionChip() => Positioned(
        top: 10,
        left: 0,
        right: 0,
        child: Center(
          child: GestureDetector(
            onTap: _showRegionPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place, color: kCyan, size: 13),
                  const SizedBox(width: 5),
                  Text('NGOFS2 · ${_region.label}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                  const Icon(Icons.arrow_drop_down,
                      color: Colors.white54, size: 16),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _timeline() {
    final f = _frames[_index];
    return Positioned(
      bottom: 18,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 14, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                      color: kCyan),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: _togglePlay,
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
                      max: (_frames.length - 1).toDouble(),
                      divisions: _frames.length - 1,
                      value: _index.toDouble(),
                      activeColor: kCyan,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        _anim?.cancel();
                        setState(() {
                          _playing = false;
                          _index = v.round();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Text(
                    f.label,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 44, right: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_frames.first.label,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 9)),
                  const Text('NGOFS2 surface-salinity forecast',
                      style: TextStyle(color: Colors.white38, fontSize: 9)),
                  Text(_frames.last.label,
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
}
