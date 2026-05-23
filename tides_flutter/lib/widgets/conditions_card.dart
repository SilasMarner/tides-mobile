import 'package:flutter/material.dart';
import '../models/tide_data.dart';
import '../theme.dart';

class ConditionsCard extends StatelessWidget {
  final Conditions c;
  const ConditionsCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) => Card(
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
                  _cell('Air Temp', _fmt(c.airTemp, '°F')),
                  _cell('Water Temp', _fmt(c.waterTemp, '°F')),
                  _cell('Pressure', _fmtPressure()),
                  _cell('Water Level', _fmt(c.waterLevel, ' ft')),
                ],
              ),
              const SizedBox(height: 8),
              _windRow(),
            ],
          ),
        ),
      );

  String _fmt(double? v, String suffix) =>
      v != null ? '${v.toStringAsFixed(1)}$suffix' : 'N/A';

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

  Widget _windRow() {
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
            '${c.windSpeed!.toStringAsFixed(0)} mph',
            if (c.windGust != null && c.windGust! > c.windSpeed! + 3)
              'G${c.windGust!.toStringAsFixed(0)}',
            if (c.beaufortStr != null) '· ${c.beaufortStr}',
          ].join(' '),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
