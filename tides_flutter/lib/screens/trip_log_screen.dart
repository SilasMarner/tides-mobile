import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/trip.dart';
import '../providers/theme_provider.dart';
import '../providers/trip_log_provider.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import 'trip_entry_screen.dart';

class TripLogScreen extends ConsumerWidget {
  const TripLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final accent = accentColor(night);
    final trips = ref.watch(tripLogProvider);

    return Scaffold(
      backgroundColor: night ? kNightBg : kNavy,
      appBar: AppBar(
        backgroundColor: appBarColor(night),
        title: Text('Trip Planner',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kCyan,
        foregroundColor: kNavy,
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const TripEntryScreen())),
        child: const Icon(Icons.add),
      ),
      body: trips.isEmpty
          ? _emptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: trips.length,
              itemBuilder: (ctx, i) => _tripTile(context, ref, trips[i]),
            ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_available, color: Colors.white24, size: 56),
              const SizedBox(height: 12),
              const Text('No trips planned yet',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TripEntryScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Plan a Trip'),
              ),
            ],
          ),
        ),
      );

  Widget _tripTile(BuildContext context, WidgetRef ref, Trip t) {
    final title = t.nickname?.isNotEmpty == true ? t.nickname! : t.stationName;
    final subtitleParts = <String>[
      DateFormat('EEE, MMM d, yyyy').format(t.plannedDate),
      if (t.alertEnabled) 'Alert ${t.leadMinutes}m before',
    ];
    return Card(
      color: kCardBg,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: t.photoPaths.isNotEmpty
              ? Image.file(File(t.photoPaths.first),
                  width: 56, height: 56, fit: BoxFit.cover)
              : Container(
                  width: 56,
                  height: 56,
                  color: kNavyLight,
                  child: const Icon(Icons.event_available, color: Colors.white38),
                ),
        ),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitleParts.join(' · '),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white38),
          onPressed: () => _confirmDelete(context, ref, t),
        ),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => TripEntryScreen(existing: t))),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Trip t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardBg,
        title: const Text('Delete trip?', style: TextStyle(color: Colors.white)),
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
      await NotificationService.cancelForTrip(t.id);
      await ref.read(tripLogProvider.notifier).remove(t.id);
    }
  }
}
