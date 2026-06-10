import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tide_data.dart';
import '../providers/detail_provider.dart'
    show kUpwellingThresholdC, sstAnomalyProvider;
import '../providers/units_provider.dart';
import '../utils/unit_format.dart';
import '../theme.dart';

class ConditionsCard extends ConsumerWidget {
  final Conditions c;
  final bool forecast; // true when showing a future day's forecast, not live obs
  const ConditionsCard({super.key, required this.c, this.forecast = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(unitsProvider);
    // The anomaly is a "today" reading — don't pin it on future-day forecasts.
    final sstAnomaly =
        forecast ? null : ref.watch(sstAnomalyProvider).valueOrNull;
    return Card(
        color: kCardBg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('CONDITIONS',
                    style: TextStyle(
                        color: kCyan, fontSize: 11, letterSpacing: 1.5)),
                const Spacer(),
                if (forecast)
                  const Text('Forecast · midday',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
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
              _windTideRow(metric),
              _waterAdvisory(),
              _upwellingAdvisory(sstAnomaly, metric),
            ],
          ),
        ),
      );
  }

  // Wind tide: how far the observed water level sits above/below the predicted
  // tide. On the TX coast, N winds drain the bays/back-lakes, S winds stack
  // water in. Hidden on forecast days and when there's no live observation.
  Widget _windTideRow(bool metric) {
    final wt = c.windTide;
    if (wt == null) return const SizedBox.shrink();
    if (wt.abs() < 0.2) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Water near predicted level',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    final above = wt > 0;
    String hint = '';
    // At/above 1 ft the dedicated advisory below spells out the cause and
    // impact, so keep this line terse and don't say "stacking" twice.
    if (wt.abs() < 1.0) {
      final dir = (c.windDirStr ?? '').toUpperCase();
      if (!above && dir.startsWith('N')) {
        hint = ' — $dir wind draining back lakes';
      } else if (above && dir.startsWith('S')) {
        hint = ' — $dir wind stacking water in';
      } else if (c.windDirStr != null) {
        hint = ' — wind tide';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(above ? Icons.arrow_upward : Icons.arrow_downward,
              color: above ? kHighTide : kLowTide, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Water ${fmtLen(wt.abs(), metric)} ${above ? 'above' : 'below'} predicted$hint',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Heads-up when the wind has stacked water well above — or drained it well
  // below — the predicted tide (|wind tide| ≥ 1 ft). Texas Gulf framing:
  // stacked water floods the open beach and back-bays; drained water leaves the
  // flats and ramps unusually low. Driven purely off the residual, so it fires
  // for any station with a live water-level reading, not just the Gulf ones.
  Widget _waterAdvisory() {
    final wt = c.windTide;
    if (wt == null || wt.abs() < 1.0) return const SizedBox.shrink();
    final high = wt > 0;
    final color = high ? const Color(0xFFFFB74D) : kCyanLight;
    final text = high
        ? 'Elevated water — beach driving and access may be limited; '
            'water stacking into the bays.'
        : 'Low water — bay flats and launch ramps may be unusually low; '
            'back-lake and beach access can be limited.';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(high ? Icons.warning_amber_rounded : Icons.info_outline,
              color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }

  // Upwelling heads-up: the daily MUR SST anomaly near the station is well
  // below normal. Worded as "likely" — a cold-front cooldown can produce the
  // same signal — but either way colder water is moving in.
  Widget _upwellingAdvisory(double? a, bool metric) {
    if (a == null || a > kUpwellingThresholdC) return const SizedBox.shrink();
    const color = kCyanLight;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.waves, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Upwelling likely — water ~${fmtTempDelta(a.abs(), metric)} '
                'colder than normal. Cooler, often nutrient-rich water moving '
                'in; bite patterns may shift.',
                style:
                    const TextStyle(color: color, fontSize: 12, height: 1.35)),
          ),
        ],
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
