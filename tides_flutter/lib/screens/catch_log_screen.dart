import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/tournaments.dart';
import '../models/catch_entry.dart';
import '../providers/captain_email_provider.dart';
import '../providers/catch_log_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/tournament_mode_provider.dart';
import '../providers/units_provider.dart';
import '../services/catch_export_service.dart';
import '../theme.dart';
import '../utils/unit_format.dart';
import 'catch_entry_screen.dart';
import 'tournament_info_screen.dart';

class CatchLogScreen extends ConsumerStatefulWidget {
  const CatchLogScreen({super.key});

  @override
  ConsumerState<CatchLogScreen> createState() => _CatchLogScreenState();
}

class _CatchLogScreenState extends ConsumerState<CatchLogScreen> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  void _toggleSelecting(bool on) {
    setState(() {
      _selecting = on;
      if (!on) _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _emailSelected(List<CatchEntry> catches, bool metric) async {
    final selected =
        catches.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;
    final recipient = ref.read(captainEmailProvider);
    try {
      await CatchExportService.emailCatches(selected,
          defaultRecipient: recipient, metric: metric);
      _toggleSelecting(false);
    } on PlatformException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'no_email_app'
          ? 'No email app is set up on this device.'
          : 'Could not send catches: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint('emailCatches failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send catches: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final night = ref.watch(nightModeProvider);
    final accent = accentColor(night);
    final catches = ref.watch(catchLogProvider);
    final metric = ref.watch(unitsProvider);
    final tournamentMode = ref.watch(tournamentModeProvider);

    return Scaffold(
      backgroundColor: night ? kNightBg : kNavy,
      appBar: AppBar(
        backgroundColor: appBarColor(night),
        title: Text(_selecting ? '${_selectedIds.length} selected' : 'Catch Log',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        leading: _selecting
            ? IconButton(
                icon: Icon(Icons.close, color: accent),
                tooltip: 'Cancel',
                onPressed: () => _toggleSelecting(false),
              )
            : null,
        actions: _selecting
            ? [
                IconButton(
                  icon: Icon(Icons.email_outlined, color: accent),
                  tooltip: 'Email selected catches',
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => _emailSelected(catches, metric),
                ),
              ]
            : [
                if (tournamentMode)
                  IconButton(
                    icon: Icon(Icons.emoji_events_outlined, color: accent),
                    tooltip: 'Tournament Info',
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const TournamentInfoScreen())),
                  ),
              ],
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              backgroundColor: kCyan,
              foregroundColor: kNavy,
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CatchEntryScreen())),
              child: const Icon(Icons.add),
            ),
      body: catches.isEmpty
          ? _emptyState(context, tournamentMode)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: catches.length,
              itemBuilder: (ctx, i) => _catchTile(
                  context, ref, catches[i], metric, tournamentMode),
            ),
    );
  }

  Widget _emptyState(BuildContext context, bool tournamentMode) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tournamentMode) ...[
                const Icon(Icons.phishing, color: Colors.white24, size: 56),
                const SizedBox(height: 12),
              ],
              const Text('No catches logged yet',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CatchEntryScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Log a Catch'),
              ),
            ],
          ),
        ),
      );

  Widget _catchTile(BuildContext context, WidgetRef ref, CatchEntry e,
      bool metric, bool tournamentMode) {
    final tournament = tournamentMode ? tournamentById(e.tournamentId) : null;
    final selected = _selectedIds.contains(e.id);
    final parts = <String>[
      if (e.lengthIn != null) fmtLenIn(e.lengthIn, metric),
      if (e.weightLb != null) fmtWeight(e.weightLb, metric),
      e.released ? 'Released' : 'Kept',
    ];
    return Card(
      color: kCardBg,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: _selecting
            ? Checkbox(
                value: selected,
                onChanged: (_) => _toggleSelected(e.id),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: e.photoPath != null
                    ? Image.file(File(e.photoPath!),
                        width: 56, height: 56, fit: BoxFit.cover)
                    : Container(
                        width: 56,
                        height: 56,
                        color: kNavyLight,
                        child:
                            const Icon(Icons.phishing, color: Colors.white38),
                      ),
              ),
        title: Text(e.species,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(parts.join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(DateFormat('MMM d, yyyy  h:mm a').format(e.caughtAt),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            if (tournament != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(tournament.name,
                      style: const TextStyle(color: kCyan, fontSize: 10)),
                ),
              ),
          ],
        ),
        trailing: _selecting
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                onPressed: () => _confirmDelete(context, ref, e.id),
              ),
        onTap: _selecting
            ? () => _toggleSelected(e.id)
            : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => CatchEntryScreen(existing: e))),
        onLongPress: _selecting ? null : () {
          _toggleSelecting(true);
          _toggleSelected(e.id);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardBg,
        title: const Text('Delete catch?', style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(catchLogProvider.notifier).remove(id);
    }
  }
}
