import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/tournaments.dart';
import '../theme.dart';

/// Shows a tournament's requirement bullets, official-rules link, and —
/// when [hasGps]/[hasPhoto] are provided — live check marks against what's
/// already filled in on the current catch. Purely informational; never
/// blocks saving a catch.
class TournamentChecklist extends StatelessWidget {
  final TournamentInfo info;
  final bool? hasGps;
  final bool? hasPhoto;
  const TournamentChecklist(
      {super.key, required this.info, this.hasGps, this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kCardBg,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.name,
                style: const TextStyle(
                    color: kCyan, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(info.species,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            if (info.gpsRequired) _statusRow('GPS coordinates', hasGps),
            if (info.photoRequired) _statusRow('Photo', hasPhoto),
            const SizedBox(height: 6),
            Text(info.measuringMethod,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.schedule, color: Colors.white54, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(info.deadline,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...info.requirements.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(color: Colors.white54)),
                      Expanded(
                        child: Text(r,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(info.officialUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16, color: kCyan),
                label: const Text('Official rules', style: TextStyle(color: kCyan)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, bool? have) {
    final ok = have == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (have != null)
            Icon(ok ? Icons.check_circle : Icons.cancel,
                color: ok ? Colors.greenAccent : Colors.orangeAccent, size: 16)
          else
            const Icon(Icons.fiber_manual_record, color: Colors.white38, size: 8),
          const SizedBox(width: 6),
          Text('$label required',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
