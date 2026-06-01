import 'package:flutter/material.dart';
import '../models/station.dart';
import '../theme.dart';

// ── Badge definitions (also used by the legend in home_screen) ───────────────

class StationBadge {
  final String key;
  final IconData icon;
  final String label;
  final String shortLabel;
  const StationBadge(this.key, this.icon, this.label, this.shortLabel);
}

const kStationBadges = [
  StationBadge('wt',   Icons.thermostat,        'Water temperature', 'water temp'),
  StationBadge('sal',  Icons.grain,             'Salinity',          'salinity'),
  StationBadge('wind', Icons.air,               'Wind speed',        'wind'),
  StationBadge('at',   Icons.wb_sunny,          'Air temperature',   'air temp'),
  StationBadge('pres', Icons.speed,             'Barometric pressure','pressure'),
  StationBadge('wl',   Icons.waves,             'Live water level',  'water level'),
];

// ── Tile ─────────────────────────────────────────────────────────────────────

class StationTile extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isFavorite;
  final Set<String>? caps;
  final Widget? dragHandle;

  const StationTile({
    super.key,
    required this.station,
    required this.onTap,
    this.onLongPress,
    this.isFavorite = false,
    this.caps,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final hasCaps = caps != null && caps!.isNotEmpty;
    return ListTile(
      isThreeLine: hasCaps,
      leading: const Icon(Icons.waves, color: kCyan),
      title: Text(station.name,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              'Station ${station.id}',
              if (station.dist != null)
                '${station.dist!.toStringAsFixed(1)} mi away',
            ].join('  ·  '),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (hasCaps) ...[
            const SizedBox(height: 4),
            _CapsBadges(caps: caps!),
          ],
        ],
      ),
      trailing: dragHandle != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFavorite)
                  const Icon(Icons.star, color: kCyan, size: 18),
                const SizedBox(width: 6),
                dragHandle!,
              ],
            )
          : isFavorite
              ? const Icon(Icons.star, color: kCyan, size: 18)
              : const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _CapsBadges extends StatelessWidget {
  final Set<String> caps;
  const _CapsBadges({required this.caps});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: kStationBadges
            .where((b) => caps.contains(b.key))
            .map((b) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(b.icon, size: 11, color: kCyan.withValues(alpha: 0.8)),
                    const SizedBox(width: 3),
                    Text(b.shortLabel,
                        style: TextStyle(
                            color: kCyan.withValues(alpha: 0.8),
                            fontSize: 10)),
                  ],
                ))
            .toList(),
      );
}
