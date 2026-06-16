import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/tournaments.dart';
import '../models/catch_entry.dart';
import '../providers/catch_log_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/units_provider.dart';
import '../theme.dart';
import '../utils/unit_format.dart';
import 'catch_entry_screen.dart';
import 'tournament_info_screen.dart';

class CatchLogScreen extends ConsumerWidget {
  const CatchLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final accent = accentColor(night);
    final catches = ref.watch(catchLogProvider);
    final metric = ref.watch(unitsProvider);

    return Scaffold(
      backgroundColor: night ? kNightBg : kNavy,
      appBar: AppBar(
        backgroundColor: appBarColor(night),
        title: Text('Catch Log',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(Icons.emoji_events_outlined, color: accent),
            tooltip: 'Tournament Info',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TournamentInfoScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kCyan,
        foregroundColor: kNavy,
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CatchEntryScreen())),
        child: const Icon(Icons.add),
      ),
      body: catches.isEmpty
          ? _emptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: catches.length,
              itemBuilder: (ctx, i) =>
                  _catchTile(context, ref, catches[i], metric),
            ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phishing, color: Colors.white24, size: 56),
              const SizedBox(height: 12),
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

  Widget _catchTile(
      BuildContext context, WidgetRef ref, CatchEntry e, bool metric) {
    final tournament = tournamentById(e.tournamentId);
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
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: e.photoPath != null
              ? Image.file(File(e.photoPath!),
                  width: 56, height: 56, fit: BoxFit.cover)
              : Container(
                  width: 56,
                  height: 56,
                  color: kNavyLight,
                  child: const Icon(Icons.phishing, color: Colors.white38),
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
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white38),
          onPressed: () => _confirmDelete(context, ref, e.id),
        ),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CatchEntryScreen(existing: e))),
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
