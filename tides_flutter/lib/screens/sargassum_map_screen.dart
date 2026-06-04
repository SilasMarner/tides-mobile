import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

// NOAA CoastWatch Caribbean & Gulf of America Regional Node — Sargassum
// Inundation Risk (SIR) v1.5.  Daily pre-rendered PNG maps showing floating
// sargassum density + ocean current arrows for 5 Gulf/Caribbean regions.
//
//   Image URL: https://cwcgom.aoml.noaa.gov/SIR/images/YYYYMMDD/REGION.png
//   Regions:   GOMF  CA  GREATER  LESSER  SA
//   Updated:   daily (~15:00 UTC previous day)
//   Source:    NOAA AOML / USF Optical Oceanography Lab (AFAI satellite)

const _sirBase = 'https://cwcgom.aoml.noaa.gov/SIR/images';

class _SirRegion {
  final String code;
  final String label;
  final double lat, lon; // approximate center for auto-pick
  const _SirRegion(this.code, this.label, this.lat, this.lon);
}

const _kRegions = <_SirRegion>[
  _SirRegion('GOMF',    'Gulf of America',    24.0, -89.0),
  _SirRegion('CA',      'Central America',    14.0, -87.0),
  _SirRegion('GREATER', 'Greater Antilles',   21.0, -75.0),
  _SirRegion('LESSER',  'Lesser Antilles',    14.5, -61.0),
  _SirRegion('SA',      'South America',       8.0, -65.0),
];

class SargassumMapScreen extends StatefulWidget {
  final double lat;
  final double lon;
  final String stationName;

  const SargassumMapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.stationName,
  });

  @override
  State<SargassumMapScreen> createState() => _SargassumMapScreenState();
}

class _SargassumMapScreenState extends State<SargassumMapScreen> {
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
  ));

  late _SirRegion _region;
  String? _date;      // "YYYYMMDD" of latest available image
  String? _imageUrl;
  bool _loading = true;
  String? _error;
  bool _outOfCoverage = false;

  @override
  void initState() {
    super.initState();
    final (region, dist) = _nearestRegion(widget.lat, widget.lon);
    _region = region;
    // SIR covers Gulf/Caribbean only. Stations far outside that area (Pacific,
    // far North Atlantic, Hawaii) default to showing the Gulf map with a note.
    _outOfCoverage = dist > 25.0;
    _load();
  }

  (_SirRegion, double) _nearestRegion(double lat, double lon) {
    _SirRegion best = _kRegions.first;
    double bestD = double.infinity;
    for (final r in _kRegions) {
      final d = math.sqrt(math.pow(r.lat - lat, 2) + math.pow(r.lon - lon, 2));
      if (d < bestD) { bestD = d; best = r; }
    }
    return (best, bestD);
  }

  /// Walk back up to 7 days to find the latest available SIR image date.
  Future<String?> _findLatestDate(String regionCode) async {
    final now = DateTime.now().toUtc();
    for (var i = 1; i <= 7; i++) {
      final d = now.subtract(Duration(days: i));
      final s = '${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
      try {
        final resp = await _dio.head('$_sirBase/$s/$regionCode.png');
        if (resp.statusCode == 200) return s;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _imageUrl = null; _date = null; });
    try {
      final date = await _findLatestDate(_region.code);
      if (date == null) {
        if (mounted) setState(() { _error = 'No sargassum image available right now'; _loading = false; });
        return;
      }
      if (!mounted) return;
      setState(() {
        _date = date;
        _imageUrl = '$_sirBase/$date/${_region.code}.png';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load sargassum map'; _loading = false; });
    }
  }

  String _fmtDate(String d) {
    // "20260602" → "Jun 2, 2026"
    if (d.length != 8) return d;
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final y = d.substring(0, 4);
    final m = int.tryParse(d.substring(4, 6)) ?? 1;
    final day = int.tryParse(d.substring(6, 8)) ?? 1;
    return '${months[m-1]} $day, $y';
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
                child: Text('SARGASSUM REGION',
                    style: TextStyle(color: kCyan, fontSize: 11, letterSpacing: 1.5)),
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
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    trailing: selected
                        ? const Icon(Icons.check, color: kCyan, size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (r.code != _region.code) {
                        setState(() { _region = r; _outOfCoverage = false; });
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
          '${widget.stationName.toUpperCase()} — SARGASSUM',
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
            child: _error != null
                ? _errorView()
                : _imageUrl == null
                    ? const SizedBox()
                    : InteractiveViewer(
                        minScale: 1,
                        maxScale: 6,
                        child: Center(
                          child: Image.network(
                            _imageUrl!,
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
                    Text('Loading sargassum map…',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null && _imageUrl != null) _infoChip(),
        ],
      ),
    );
  }

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

  Widget _infoChip() => Positioned(
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
                  const Icon(Icons.grass, color: kCyan, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    '${_region.label}${_outOfCoverage ? ' (nearest)' : ''}'
                    '${_date != null ? ' · ${_fmtDate(_date!)}' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 16),
                ],
              ),
            ),
          ),
        ),
      );
}
