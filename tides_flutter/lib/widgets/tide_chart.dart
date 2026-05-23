import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/tide_data.dart';
import '../theme.dart';

class TideChart extends StatelessWidget {
  final Map<int, double> hourly;
  final List<TidePrediction> hilo;
  final bool isToday;

  const TideChart({
    super.key,
    required this.hourly,
    required this.hilo,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var h = 0; h < 24; h++) {
      if (hourly.containsKey(h)) {
        spots.add(FlSpot(h.toDouble(), hourly[h]!));
      }
    }
    if (spots.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
            child: Text('No chart data', style: TextStyle(color: Colors.white38))),
      );
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 0.5;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 0.5;
    final nowX = isToday
        ? DateTime.now().hour + DateTime.now().minute / 60.0
        : -1.0;

    return SizedBox(
      height: 160,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 23,
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 2,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.white10, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                  '${s.y.toStringAsFixed(2)} ft',
                  const TextStyle(color: kCyan, fontWeight: FontWeight.bold, fontSize: 12),
                )).toList(),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (v, _) => Text(
                    v.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 6,
                  getTitlesWidget: (v, _) {
                    final h = v.toInt();
                    if (h == 0) return _axisLabel('12a');
                    if (h == 6) return _axisLabel('6a');
                    if (h == 12) return _axisLabel('12p');
                    if (h == 18) return _axisLabel('6p');
                    return const SizedBox.shrink();
                  },
                ),
              ),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            extraLinesData: nowX >= 0
                ? ExtraLinesData(verticalLines: [
                    VerticalLine(
                      x: nowX,
                      color: Colors.amber.withOpacity(0.7),
                      strokeWidth: 2,
                      dashArray: [4, 4],
                    ),
                  ])
                : null,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: kCyan,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) {
                    return hilo.any((p) =>
                        (p.time.hour + p.time.minute / 60 - spot.x).abs() <
                        0.5);
                  },
                  getDotPainter: (spot, _, __, ___) {
                    final isHigh = hilo.any((p) =>
                        p.type == 'H' &&
                        (p.time.hour + p.time.minute / 60 - spot.x).abs() <
                            0.5);
                    return FlDotCirclePainter(
                      radius: 4,
                      color: isHigh ? kHighTide : kLowTide,
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: kCyan.withOpacity(0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _axisLabel(String t) =>
      Text(t, style: const TextStyle(color: Colors.white38, fontSize: 10));
}
