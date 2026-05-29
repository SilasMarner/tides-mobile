import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tide_data.dart';
import '../providers/units_provider.dart';
import '../utils/unit_format.dart';
import '../theme.dart';

class ConditionsCard extends ConsumerWidget {
  final Conditions c;
  const ConditionsCard({super.key, required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(unitsProvider);
    return Card(
        color: kCardBg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CONDITIONS',
                  style: TextStyle(
                      color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _cell('Air Temp', fmtTemp(c.airTemp, metric)),
                  _cell('Water Temp', fmtTemp(c.waterTemp, metric)),
                  _cell('Pressure', _fmtPressure()),
                  _cell('Water Level', fmtLen(c.waterLevel, metric)),
                ],
              ),
              if (c.salinity != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  _cell('Salinity', '${c.salinity!.toStringAsFixed(1)} ppt'),
                  const Expanded(child: SizedBox()),
                  const Expanded(child: SizedBox()),
                  const Expanded(child: SizedBox()),
                ]),
              ],
              const SizedBox(height: 8),
              _windRow(metric),
            ],
          ),
        ),
      );
  }

  String _fmtPressure() {
    if (c.pressure == null) return 'N/A';
    final arrow = c.pressureTrend > 0
        ? ' ↑'
        : c.pressureTrend < 0
            ? ' ↓'
            : '';
    return '${c.pressure!.toStringAsFixed(1)} mb$arrow';
  }

  Widget _cell(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _windRow(bool metric) {
    if (c.windSpeed == null) {
      return const Text('Wind  N/A',
          style: TextStyle(color: Colors.white54, fontSize: 12));
    }
    return Row(
      children: [
        const Text('Wind  ',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        Text(
          [
            if (c.windDirStr != null) c.windDirStr!,
            fmtSpeed(c.windSpeed!, metric),
            if (c.windGust != null && c.windGust! > c.windSpeed! + 3)
              'gusts ${fmtSpeed(c.windGust!, metric)}',
            if (c.beaufortStr != null) '— ${c.beaufortStr}',
          ].join(' '),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
