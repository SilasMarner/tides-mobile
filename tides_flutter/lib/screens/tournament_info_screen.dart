import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tournaments.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';
import '../widgets/tournament_checklist.dart';

class TournamentInfoScreen extends ConsumerWidget {
  const TournamentInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final accent = accentColor(night);
    return Scaffold(
      backgroundColor: night ? kNightBg : kNavy,
      appBar: AppBar(
        backgroundColor: appBarColor(night),
        title: Text('Tournament Info',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kTournaments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => TournamentChecklist(info: kTournaments[i]),
      ),
    );
  }
}
