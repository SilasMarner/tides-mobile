import 'package:flutter/material.dart';
import '../models/station.dart';
import '../theme.dart';

class StationTile extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;
  final bool isFavorite;

  const StationTile({
    super.key,
    required this.station,
    required this.onTap,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.waves, color: kCyan),
        title: Text(station.name,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(
          [
            'Station ${station.id}',
            if (station.dist != null)
              '${station.dist!.toStringAsFixed(1)} mi away',
          ].join('  ·  '),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: isFavorite
            ? const Icon(Icons.star, color: kCyan, size: 18)
            : const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );
}
