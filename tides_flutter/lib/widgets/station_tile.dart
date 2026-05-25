import 'package:flutter/material.dart';
import '../models/station.dart';
import '../theme.dart';

// ── Badge definitions (also used by the legend in home_screen) ───────────────

class StationBadge {
  final String key;
  final IconData icon;
  final String label;
  const StationBadge(this.key, this.icon, this.label);
}

const kStationBadges = [
  StationBadge('wl',   Icons.water,             'Live water level'),
  StationBadge('wt',   Icons.thermostat,          'Water temperature'),
  StationBadge('sal',  Icons.water_drop,           'Salinity'),
  StationBadge('wind', Icons.air,                 'Wind'),
  StationBadge('at',   Icons.device_thermostat,   'Air temperature'),
  StationBadge('pres', Icons.speed,               'Barometric pressure'),
];

// ── Tile ─────────────────────────────────────────────────────────────────────

class StationTile extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;
  final bool isFavorite;
  final Set<String>? caps;

  const StationTile({
    super.key,
    required this.station,
    required this.onTap,
    this.isFavorite = false,
    this.caps,
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
      trailing: isFavorite
          ? const Icon(Icons.star, color: kCyan, size: 18)
          : const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _CapsBadges extends StatelessWidget {
  final Set<String> caps;
  const _CapsBadges({required this.caps});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: kStationBadges
            .where((b) => caps.contains(b.key))
            .map((b) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: b.label,
                    child: Icon(b.icon,
                        size: 13, color: kCyan.withValues(alpha: 0.65)),
                  ),
                ))
            .toList(),
      );
}
