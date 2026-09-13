import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
import '../models/trip.dart';
import '../providers/favorites_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/trip_log_provider.dart';
import '../providers/units_provider.dart';
import '../services/noaa_api.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../utils/unit_format.dart';

class TripEntryScreen extends ConsumerStatefulWidget {
  final Trip? existing;
  const TripEntryScreen({super.key, this.existing});

  @override
  ConsumerState<TripEntryScreen> createState() => _TripEntryScreenState();
}

class _TripEntryScreenState extends ConsumerState<TripEntryScreen> {
  final _nicknameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Station? _station;
  late DateTime _plannedDate;
  bool _alertEnabled = false;
  int _leadMinutes = 30;
  List<String> _photoPaths = [];
  String? _weatherSnapshot;
  DateTime? _weatherSnapshotAt;
  bool _saving = false;
  bool _refreshingWeather = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nicknameCtrl.text = e.nickname ?? '';
      _notesCtrl.text = e.notes ?? '';
      _station = Station(id: e.stationId, name: e.stationName, lat: e.lat, lon: e.lon);
      _plannedDate = e.plannedDate;
      _alertEnabled = e.alertEnabled;
      _leadMinutes = e.leadMinutes;
      _photoPaths = List.of(e.photoPaths);
      _weatherSnapshot = e.weatherSnapshot;
      _weatherSnapshotAt = e.weatherSnapshotAt;
    } else {
      final now = DateTime.now();
      _plannedDate = DateTime(now.year, now.month, now.day);
      final favorites = ref.read(favoritesProvider);
      if (favorites.isNotEmpty) _station = favorites.first;
    }
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStation() async {
    final favorites = ref.read(favoritesProvider);
    if (favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a favorite station first, then plan a trip there.')));
      return;
    }
    final picked = await showModalBottomSheet<Station>(
      context: context,
      backgroundColor: kCardBg,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in favorites)
              ListTile(
                leading: const Icon(Icons.star, color: kCyan),
                title: Text(s.name, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _station = picked);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _plannedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    setState(() => _plannedDate = DateTime(date.year, date.month, date.day));
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: kCardBg,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: kCyan),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: kCyan),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    final id = widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/trip_photos/$id');
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
    final dest = '${photosDir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(picked.path).copy(dest);
    if (!mounted) return;
    setState(() => _photoPaths = [..._photoPaths, dest]);
  }

  void _removePhoto(String path) {
    setState(() => _photoPaths = _photoPaths.where((p) => p != path).toList());
    File(path).delete().catchError((_) => File(path));
  }

  // Fetches TideData for [station]/[date] and derives the best bite window
  // for that day via computeBiteWindows — which, unlike TideData.fishing.windows,
  // works for any date, not just today (see noaa_api.dart's fetchAllData).
  Future<(BiteWindow?, String)> _fetchWindowAndSnapshot(
      Station station, DateTime date, bool metric) async {
    final data = await fetchAllData(station, targetDate: date);
    final bite = computeBiteWindows(data.hourly, data.solunar);
    final window = bite.windows.isNotEmpty ? bite.windows.first : null;

    final c = data.conditions;
    final isToday = data.isToday;
    final header = isToday
        ? 'Conditions @ ${station.name} (${DateFormat('MMM d, h:mm a').format(DateTime.now())})'
        : 'Forecast @ ${station.name} (${DateFormat('MMM d').format(data.targetDate)}, midday)';
    final lines = <String>[header];
    if (bite.movement != null) lines.add('Tide: ${bite.movement}');
    if (c.waterLevel != null) lines.add('Water level: ${fmtLen(c.waterLevel, metric)}');
    if (c.waterTemp != null) lines.add('Water temp: ${fmtTemp(c.waterTemp, metric)}');
    if (c.airTemp != null) lines.add('Air temp: ${fmtTemp(c.airTemp, metric)}');
    if (c.pressure != null) {
      final arrow = c.pressureTrend > 0 ? ' ↑' : c.pressureTrend < 0 ? ' ↓' : '';
      lines.add('Barometer: ${c.pressure!.toStringAsFixed(1)} mb$arrow');
    }
    if (c.windSpeed != null) {
      final wind = [
        if (c.windDirStr != null) c.windDirStr!,
        fmtSpeed(c.windSpeed!, metric),
        if (c.windGust != null && c.windGust! > c.windSpeed! + 3)
          'gusts ${fmtSpeed(c.windGust!, metric)}',
      ].join(' ');
      lines.add('Wind: $wind');
    }
    lines.add('Moon: ${data.moon.phase} (${data.moon.pct}%)');
    if (window != null) {
      lines.add('Best window: ${_fmtHour(window.startH)}–${_fmtHour(window.endH)} '
          '(${window.reason})');
    }
    return (window, lines.join('\n'));
  }

  static String _fmtHour(double h) {
    final hour = h.floor();
    final min = ((h - hour) * 60).round();
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h12:${min.toString().padLeft(2, '0')} $ampm';
  }

  Future<void> _refreshWeatherLog() async {
    final station = _station;
    if (station == null) return;
    setState(() => _refreshingWeather = true);
    try {
      final metric = ref.read(unitsProvider);
      final (_, snapshot) = await _fetchWindowAndSnapshot(station, _plannedDate, metric);
      if (!mounted) return;
      setState(() {
        _weatherSnapshot = snapshot;
        _weatherSnapshotAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load conditions — check your connection and try again.')));
    } finally {
      if (mounted) setState(() => _refreshingWeather = false);
    }
  }

  Future<void> _save() async {
    final station = _station;
    if (station == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a station for this trip.')));
      return;
    }
    setState(() => _saving = true);
    final id = widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    var trip = Trip(
      id: id,
      nickname: _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
      stationId: station.id,
      stationName: station.name,
      lat: station.lat,
      lon: station.lon,
      plannedDate: _plannedDate,
      alertEnabled: _alertEnabled,
      leadMinutes: _leadMinutes,
      photoPaths: _photoPaths,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      weatherSnapshot: _weatherSnapshot,
      weatherSnapshotAt: _weatherSnapshotAt,
    );
    final notifier = ref.read(tripLogProvider.notifier);
    if (widget.existing == null) {
      await notifier.add(trip);
    } else {
      await notifier.update(trip);
    }

    // Best-effort: schedule/cancel the alert and capture an initial weather
    // snapshot if one hasn't been taken yet. The trip is already saved above
    // regardless of whether this succeeds (e.g. offline).
    try {
      final metric = ref.read(unitsProvider);
      final (window, snapshot) =
          await _fetchWindowAndSnapshot(station, _plannedDate, metric);
      await NotificationService.scheduleTripAlert(trip, window);
      if (trip.weatherSnapshot == null) {
        trip = trip.copyWith(weatherSnapshot: snapshot, weatherSnapshotAt: DateTime.now());
        await notifier.update(trip);
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final night = ref.watch(nightModeProvider);
    final accent = accentColor(night);
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: night ? kNightBg : kNavy,
      appBar: AppBar(
        backgroundColor: appBarColor(night),
        title: Text(widget.existing == null ? 'Plan a Trip' : 'Edit Trip',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nicknameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Trip nickname (optional)',
              hintText: 'e.g. Fall redfish run',
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('LOCATION'),
          const SizedBox(height: 8),
          Card(
            color: kCardBg,
            child: ListTile(
              leading: const Icon(Icons.star, color: kCyan),
              title: Text(_station?.name ?? 'Pick a favorite station',
                  style: const TextStyle(color: Colors.white)),
              subtitle: favorites.isEmpty
                  ? const Text('No favorites yet — add one from the home screen',
                      style: TextStyle(color: Colors.white54, fontSize: 12))
                  : null,
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: _pickStation,
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('DATE'),
          const SizedBox(height: 8),
          Card(
            color: kCardBg,
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: kCyan),
              title: Text(DateFormat('EEEE, MMM d, yyyy').format(_plannedDate),
                  style: const TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('BEST-TIME ALERT'),
          const SizedBox(height: 8),
          Card(
            color: kCardBg,
            child: Column(
              children: [
                SwitchListTile(
                  activeThumbColor: kCyan,
                  title: const Text('Alert before the best window',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Same lead-time alert as tide/solunar notifications',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: _alertEnabled,
                  onChanged: (v) => setState(() => _alertEnabled = v),
                ),
                if (_alertEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [15, 30, 45, 60].map((m) {
                        final selected = _leadMinutes == m;
                        return GestureDetector(
                          onTap: () => setState(() => _leadMinutes = m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? kCyan : kNavy,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: selected ? kCyan : Colors.white24),
                            ),
                            child: Text('${m}m',
                                style: TextStyle(
                                    color: selected ? kNavy : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('PHOTOS'),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in _photoPaths)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(p),
                              width: 76, height: 76, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: -6, right: -6,
                          child: IconButton(
                            icon: const Icon(Icons.cancel,
                                color: Colors.white70, size: 20),
                            onPressed: () => _removePhoto(p),
                          ),
                        ),
                      ],
                    ),
                  ),
                InkWell(
                  onTap: _addPhoto,
                  child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.add_a_photo, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('WEATHER & TIDE LOG'),
          const SizedBox(height: 8),
          Card(
            color: kCardBg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _weatherSnapshot ??
                        'Not captured yet — saved automatically once you save this trip.',
                    style: TextStyle(
                        color: _weatherSnapshot == null
                            ? Colors.white54
                            : Colors.white70,
                        fontSize: 12,
                        height: 1.4),
                  ),
                  if (_weatherSnapshotAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          'Captured ${DateFormat('MMM d, h:mm a').format(_weatherSnapshotAt!)}',
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _station == null || _refreshingWeather
                          ? null
                          : _refreshWeatherLog,
                      icon: _refreshingWeather
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kCyan))
                          : const Icon(Icons.refresh, size: 16, color: kCyan),
                      label: Text(
                          _weatherSnapshot == null ? 'Capture now' : 'Refresh',
                          style: const TextStyle(color: kCyan)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 16),
          _readinessChecklist(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Trip'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: kCyan, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1));

  Widget _readinessChecklist() {
    final rows = <(String, bool)>[
      ('Station picked', _station != null),
      ('Date set', true),
      ('Best-time alert configured', _alertEnabled),
      ('Photo added', _photoPaths.isNotEmpty),
    ];
    return Card(
      color: kCardBg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('READY TO GO?',
                style: TextStyle(
                    color: kCyan, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            for (final (label, ok) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: ok ? Colors.greenAccent : Colors.white38, size: 16),
                    const SizedBox(width: 6),
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
