import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../data/tournaments.dart';
import '../models/catch_entry.dart';
import '../providers/catch_log_provider.dart';
import '../providers/detail_provider.dart';
import '../providers/last_tournament_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/tournament_mode_provider.dart';
import '../providers/units_provider.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/unit_format.dart';
import '../widgets/tournament_checklist.dart';

const _kSpecies = [
  'Redfish',
  'Speckled Trout',
  'Flounder',
  'Black Drum',
  'Sheepshead',
  'Snook',
  'Tarpon',
  'Spanish Mackerel',
  'King Mackerel',
  'Bull Shark',
  'Blacktip Shark',
  'Hammerhead Shark',
  'Bonnethead Shark',
  'Tiger Shark',
  'Atlantic Sharpnose Shark',
  'Blacknose Shark',
  'Spinner Shark',
  'Sandbar Shark',
  'Lemon Shark',
  'Nurse Shark',
  'Finetooth Shark',
  'Dusky Shark',
  'Smooth Hammerhead',
  'Great Hammerhead',
  'Scalloped Hammerhead',
  'Shortfin Mako',
  'Largemouth Bass',
  'Striped Bass',
  'Crappie',
  'Catfish',
  'Bluegill',
  'Other',
];

/// Every shark species found in Texas Gulf waters. Shown as the species
/// options when a shark tournament (e.g. Texas Shark Rodeo) is selected, so
/// the picker stays on-target and excludes freshwater/inshore non-sharks.
const _kSharkSpecies = [
  'Atlantic Sharpnose Shark',
  'Blacknose Shark',
  'Blacktip Shark',
  'Spinner Shark',
  'Bull Shark',
  'Bonnethead Shark',
  'Scalloped Hammerhead',
  'Great Hammerhead',
  'Smooth Hammerhead',
  'Sandbar Shark',
  'Lemon Shark',
  'Nurse Shark',
  'Tiger Shark',
  'Finetooth Shark',
  'Dusky Shark',
  'Silky Shark',
  'Sand Tiger Shark',
  'Shortfin Mako',
  'Longfin Mako',
  'Night Shark',
  'Oceanic Whitetip Shark',
  'Caribbean Reef Shark',
  'Smalltail Shark',
  'Bignose Shark',
  'Galapagos Shark',
  'Narrowtooth Shark',
  'Common Thresher Shark',
  'Bigeye Thresher Shark',
  'Porbeagle',
  'Atlantic Angel Shark',
  'Other Shark',
];

class CatchEntryScreen extends ConsumerStatefulWidget {
  final CatchEntry? existing;
  const CatchEntryScreen({super.key, this.existing});

  @override
  ConsumerState<CatchEntryScreen> createState() => _CatchEntryScreenState();
}

class _CatchEntryScreenState extends ConsumerState<CatchEntryScreen> {
  final _speciesCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _girthCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _forkLengthCtrl = TextEditingController();
  final _tagNumberCtrl = TextEditingController();
  final _dnaSampleCtrl = TextEditingController();
  final _recaptureTagCtrl = TextEditingController();

  late DateTime _caughtAt;
  bool _released = true;
  bool _saveGps = true;
  double? _lat;
  double? _lon;
  String? _locationLabel;
  String? _photoPath;
  String? _tournamentId;
  bool _gettingLocation = false;
  bool _saving = false;
  String _sex = 'Unknown';
  bool _isRecapture = false;
  DateTime? _releasedAt;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final metric = ref.read(unitsProvider);
    _caughtAt = e?.caughtAt ?? DateTime.now();
    _speciesCtrl.text = e?.species ?? '';
    if (e?.lengthIn != null) {
      final v = metric ? e!.lengthIn! * 2.54 : e!.lengthIn!;
      _lengthCtrl.text = v.toStringAsFixed(1);
    }
    if (e?.girthIn != null) {
      final v = metric ? e!.girthIn! * 2.54 : e!.girthIn!;
      _girthCtrl.text = v.toStringAsFixed(1);
    }
    if (e?.weightLb != null) {
      final v = metric ? e!.weightLb! * 0.453592 : e!.weightLb!;
      _weightCtrl.text = v.toStringAsFixed(1);
    }
    _notesCtrl.text = e?.notes ?? '';
    _released = e?.released ?? true;
    _lat = e?.lat;
    _lon = e?.lon;
    _saveGps = e == null || e.lat != null;
    _locationLabel = e?.locationLabel;
    _photoPath = e?.photoPath;
    _tournamentId = e?.tournamentId ?? ref.read(lastTournamentProvider);
    if (e?.forkLengthIn != null) {
      final v = metric ? e!.forkLengthIn! * 2.54 : e!.forkLengthIn!;
      _forkLengthCtrl.text = v.toStringAsFixed(1);
    }
    _tagNumberCtrl.text = e?.tagNumber ?? '';
    _dnaSampleCtrl.text = e?.dnaSampleNumber ?? '';
    _recaptureTagCtrl.text = e?.recaptureTagNumber ?? '';
    _sex = e?.sex ?? 'Unknown';
    _isRecapture = e?.isRecapture ?? false;
    _releasedAt = e?.releasedAt ?? (_released ? _caughtAt : null);
  }

  @override
  void dispose() {
    _speciesCtrl.dispose();
    _lengthCtrl.dispose();
    _girthCtrl.dispose();
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    _forkLengthCtrl.dispose();
    _tagNumberCtrl.dispose();
    _dnaSampleCtrl.dispose();
    _recaptureTagCtrl.dispose();
    super.dispose();
  }

  double? _parseLen(String s, bool metric) {
    final v = double.tryParse(s.trim());
    if (v == null) return null;
    return metric ? v / 2.54 : v;
  }

  double? _parseWeight(String s, bool metric) {
    final v = double.tryParse(s.trim());
    if (v == null) return null;
    return metric ? v / 0.453592 : v;
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingLocation = true);
    final loc = await getLocation();
    if (!mounted) return;
    setState(() {
      _gettingLocation = false;
      if (loc != null) {
        final (lat, lon, label) = loc;
        _lat = lat;
        _lon = lon;
        _locationLabel = label;
      }
    });
    if (loc == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get current location')),
      );
    }
  }

  Future<void> _pickPhoto() async {
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

    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/catch_photos');
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
    final dest = '${photosDir.path}/$id.jpg';
    await File(picked.path).copy(dest);
    if (!mounted) return;
    setState(() => _photoPath = dest);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _caughtAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_caughtAt),
    );
    if (!mounted) return;
    setState(() {
      _caughtAt = DateTime(date.year, date.month, date.day,
          time?.hour ?? _caughtAt.hour, time?.minute ?? _caughtAt.minute);
    });
  }

  Future<void> _pickReleaseDate() async {
    final base = _releasedAt ?? _caughtAt;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    setState(() {
      _releasedAt = DateTime(date.year, date.month, date.day,
          time?.hour ?? base.hour, time?.minute ?? base.minute);
    });
  }

  Future<void> _save() async {
    final species = _speciesCtrl.text.trim();
    if (species.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a species')));
      return;
    }
    setState(() => _saving = true);
    final metric = ref.read(unitsProvider);
    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final entry = CatchEntry(
      id: id,
      species: species,
      caughtAt: _caughtAt,
      lengthIn: _parseLen(_lengthCtrl.text, metric),
      girthIn: _parseLen(_girthCtrl.text, metric),
      weightLb: _parseWeight(_weightCtrl.text, metric),
      released: _released,
      lat: _saveGps ? _lat : null,
      lon: _saveGps ? _lon : null,
      locationLabel: _saveGps ? _locationLabel : null,
      photoPath: _photoPath,
      tournamentId: _tournamentId,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      forkLengthIn: _parseLen(_forkLengthCtrl.text, metric),
      tagNumber:
          _tagNumberCtrl.text.trim().isEmpty ? null : _tagNumberCtrl.text.trim(),
      dnaSampleNumber: _dnaSampleCtrl.text.trim().isEmpty
          ? null
          : _dnaSampleCtrl.text.trim(),
      sex: _sex,
      isRecapture: _isRecapture,
      recaptureTagNumber: _isRecapture && _recaptureTagCtrl.text.trim().isNotEmpty
          ? _recaptureTagCtrl.text.trim()
          : null,
      releasedAt: _released ? _releasedAt : null,
    );
    if (_isEdit) {
      await ref.read(catchLogProvider.notifier).update(entry);
    } else {
      await ref.read(catchLogProvider.notifier).add(entry);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final night = ref.watch(nightModeProvider);
    final accent = accentColor(night);
    final metric = ref.watch(unitsProvider);
    final lengthUnit = metric ? 'cm' : 'in';
    final weightUnit = metric ? 'kg' : 'lb';
    final tournamentMode = ref.watch(tournamentModeProvider);
    final tournament = tournamentMode ? tournamentById(_tournamentId) : null;
    final isTsr = tournament?.id == 'tsr';
    final speciesOptions = isTsr ? _kSharkSpecies : _kSpecies;

    return Scaffold(
      backgroundColor: night ? kNightBg : kNavy,
      appBar: AppBar(
        backgroundColor: appBarColor(night),
        title: Text(_isEdit ? 'Edit Catch' : 'Log a Catch',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Photo first — set the visual identity of the catch up top.
          if (_photoPath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(_photoPath!),
                  height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Change Photo'),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _photoPath = null),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.redAccent),
                  label: const Text('Remove',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ] else
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add Photo'),
            ),
          const SizedBox(height: 16),
          // Tournament first — selecting a shark tournament narrows the species
          // list to sharks only and drives which extra fields appear below.
          if (tournamentMode) ...[
            DropdownButtonFormField<String?>(
              initialValue: _tournamentId,
              decoration:
                  const InputDecoration(labelText: 'Tournament (optional)'),
              dropdownColor: kCardBg,
              style: const TextStyle(color: Colors.white),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...kTournaments.map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
              ],
              onChanged: (v) {
                setState(() {
                  _tournamentId = v;
                  // Dropping a freshwater pick when switching into a shark
                  // tournament keeps the species consistent with the list.
                  if (tournamentById(v)?.id == 'tsr' &&
                      !_kSharkSpecies.contains(_speciesCtrl.text)) {
                    _speciesCtrl.clear();
                  }
                });
                ref.read(lastTournamentProvider.notifier).setId(v);
              },
            ),
            const SizedBox(height: 12),
          ],
          // What & when.
          Autocomplete<String>(
            // Re-seed the field from _speciesCtrl when the shark/non-shark mode
            // flips, so a cleared freshwater pick actually disappears.
            key: ValueKey(isTsr),
            initialValue: TextEditingValue(text: _speciesCtrl.text),
            optionsBuilder: (v) {
              if (v.text.isEmpty) return speciesOptions;
              return speciesOptions.where(
                  (s) => s.toLowerCase().contains(v.text.toLowerCase()));
            },
            onSelected: (s) => _speciesCtrl.text = s,
            fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
              return TextField(
                controller: ctrl,
                focusNode: focus,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Species *'),
                onChanged: (v) => _speciesCtrl.text = v,
              );
            },
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date & time'),
              child: Text(DateFormat('MMM d, yyyy  h:mm a').format(_caughtAt),
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          // Measurements grouped together — fork length sits with the rest.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lengthCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(labelText: 'Length ($lengthUnit)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _girthCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(labelText: 'Girth ($lengthUnit)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isTsr) ...[
            TextField(
              controller: _forkLengthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration:
                  InputDecoration(labelText: 'Fork length ($lengthUnit)'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: 'Weight ($weightUnit)'),
          ),
          const SizedBox(height: 16),
          // Kept vs released — release time follows directly when relevant.
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Kept')),
              ButtonSegment(value: true, label: Text('Released')),
            ],
            selected: {_released},
            onSelectionChanged: (s) => setState(() {
              _released = s.first;
              if (_released && _releasedAt == null) _releasedAt = _caughtAt;
            }),
          ),
          if (isTsr && _released) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickReleaseDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Time released'),
                child: Text(
                  _releasedAt != null
                      ? DateFormat('MMM d, yyyy  h:mm a').format(_releasedAt!)
                      : 'Tap to set',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Tournament-specific tagging details.
          if (isTsr) ...[
            _tsrDetailsCard(),
            const SizedBox(height: 16),
          ],
          // Where.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save location with this catch',
                style: TextStyle(color: Colors.white)),
            value: _saveGps,
            activeColor: kCyan,
            onChanged: (v) => setState(() => _saveGps = v),
          ),
          if (_saveGps) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _lat != null && _lon != null
                        ? '${_locationLabel ?? 'Location'}: '
                            '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}'
                        : 'No location captured yet',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _gettingLocation ? null : _useCurrentLocation,
                  child: _gettingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Use current location'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _insertConditionsSnapshot,
              icon: const Icon(Icons.cloud_outlined, size: 18, color: kCyan),
              label: const Text('Add current conditions',
                  style: TextStyle(color: kCyan)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Save Changes' : 'Save Catch'),
            ),
          ),
          if (tournament != null) ...[
            const SizedBox(height: 16),
            TournamentChecklist(
              info: tournament,
              hasGps: _saveGps && _lat != null,
              hasPhoto: _photoPath != null,
            ),
          ],
        ],
      ),
    );
  }

  /// Appends a snapshot of the most recently loaded tide/weather conditions
  /// (from the station the user last opened) to the Notes field, so the catch
  /// carries the tide stage, water/air temp, barometer, wind, etc. from when it
  /// was logged. No-op with a hint if no station has been viewed this session.
  void _insertConditionsSnapshot() {
    final metric = ref.read(unitsProvider);
    final station = ref.read(selectedStationProvider);
    final data = ref.read(tideDataProvider).valueOrNull;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No conditions loaded yet — open a tide station first, then come back.')));
      return;
    }
    final c = data.conditions;
    final where = station?.name ?? 'Station ${data.stationId}';
    // Live obs only exist for today; a future-dated station view is a forecast.
    final header = data.isToday
        ? '— Conditions @ $where '
            '(${DateFormat('MMM d, h:mm a').format(DateTime.now())}) —'
        : '— Forecast @ $where '
            '(${DateFormat('MMM d').format(data.targetDate)}, midday) —';
    final lines = <String>[header];
    if (data.fishing.movement != null) {
      lines.add('Tide: ${data.fishing.movement}');
    }
    if (c.waterLevel != null) {
      lines.add('Water level: ${fmtLen(c.waterLevel, metric)}');
    }
    if (c.waterTemp != null) {
      lines.add('Water temp: ${fmtTemp(c.waterTemp, metric)}');
    }
    if (c.airTemp != null) lines.add('Air temp: ${fmtTemp(c.airTemp, metric)}');
    if (c.pressure != null) {
      final arrow = c.pressureTrend > 0
          ? ' ↑'
          : c.pressureTrend < 0
              ? ' ↓'
              : '';
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
    if (c.salinity != null) {
      lines.add('Salinity: ${c.salinity!.toStringAsFixed(1)} ppt');
    }
    lines.add('Moon: ${data.moon.phase} (${data.moon.pct}%)');
    final snapshot = lines.join('\n');
    final existing = _notesCtrl.text.trimRight();
    _notesCtrl.text = existing.isEmpty ? snapshot : '$existing\n\n$snapshot';
    setState(() {});
  }

  Widget _tsrDetailsCard() => Card(
        color: kCardBg,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Texas Shark Rodeo Details',
                  style: TextStyle(
                      color: kCyan, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              const Text('Sex',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Male', label: Text('Male')),
                  ButtonSegment(value: 'Female', label: Text('Female')),
                  ButtonSegment(value: 'Unknown', label: Text('Unknown')),
                ],
                selected: {_sex},
                onSelectionChanged: (s) => setState(() => _sex = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagNumberCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Tag number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dnaSampleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'DNA sample number'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('This is a recapture',
                    style: TextStyle(color: Colors.white)),
                value: _isRecapture,
                activeColor: kCyan,
                onChanged: (v) => setState(() => _isRecapture = v),
              ),
              if (_isRecapture)
                TextField(
                  controller: _recaptureTagCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: 'Original tag number',
                      helperText: 'The tag already on the shark when recaptured',
                      helperStyle: TextStyle(color: Colors.white38)),
                ),
            ],
          ),
        ),
      );
}
