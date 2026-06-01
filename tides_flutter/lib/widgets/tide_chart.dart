import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/tide_data.dart';
import '../theme.dart';

class TideChart extends StatefulWidget {
  final Map<int, double> hourly;
  final List<TidePrediction> hilo;
  final bool isToday;
  final bool metric;
  final SolunarInfo? solunar;

  const TideChart({
    super.key,
    required this.hourly,
    required this.hilo,
    required this.isToday,
    this.metric = false,
    this.solunar,
  });

  @override
  State<TideChart> createState() => _TideChartState();
}

class _TideChartState extends State<TideChart> {
  double? _touchX;
  double? _touchY;

  double get _unitScale => widget.metric ? 0.3048 : 1.0;

  // Interpolate to 30-min resolution for smoother touch snapping
  List<FlSpot> _buildSpots() {
    final s = _unitScale;
    final spots = <FlSpot>[];
    for (var h = 0; h < 24; h++) {
      final v = widget.hourly[h];
      if (v == null) continue;
      spots.add(FlSpot(h.toDouble(), v * s));
      // Add half-hour point via cosine interpolation to next hour
      final vNext = widget.hourly[h + 1];
      if (vNext != null) {
        final mid = v + (vNext - v) * (1 - _cos01(0.5)) ;
        spots.add(FlSpot(h + 0.5, mid * s));
      }
    }
    return spots;
  }

  // Cosine ease [0,1] → [0,1], used for tide-curve-shaped interpolation
  double _cos01(double t) => (1 - _cosD(t * 180)) / 2;
  double _cosD(double deg) {
    const pi = 3.141592653589793;
    return _cos(deg * pi / 180);
  }
  double _cos(double rad) {
    // Simple Taylor series cos — avoids dart:math import
    double r = 1, t = 1;
    for (var i = 1; i <= 8; i++) {
      t *= -rad * rad / ((2 * i - 1) * (2 * i));
      r += t;
    }
    return r;
  }

  String _fmtX(double x) {
    final totalMin = (x * 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final suffix = h < 12 ? 'AM' : 'PM';
    return '$h12:${m.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final spots = _buildSpots();
    if (spots.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
            child: Text('No chart data', style: TextStyle(color: Colors.white38))),
      );
    }

    final pad = widget.metric ? 0.2 : 0.5;
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - pad;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + pad;
    final nowX = widget.isToday
        ? DateTime.now().hour + DateTime.now().minute / 60.0
        : -1.0;

    final verticalLines = <VerticalLine>[
      if (nowX >= 0)
        VerticalLine(
          x: nowX,
          color: Colors.amber.withValues(alpha: 0.7),
          strokeWidth: 2,
          dashArray: [4, 4],
        ),
      if (_touchX != null)
        VerticalLine(
          x: _touchX!,
          color: Colors.white.withValues(alpha: 0.5),
          strokeWidth: 1.5,
        ),
    ];

    // Solunar feeding-period markers (hours of day), like the Grafana dashboard:
    // solid green = major (peak), dashed green = minor.
    final sol = widget.solunar;
    if (sol != null) {
      const solGreen = Color(0xFF66BB6A);
      void addSol(double t, bool major) {
        if (t < 0 || t > 23) return; // off-chart
        verticalLines.add(VerticalLine(
          x: t,
          color: solGreen.withValues(alpha: major ? 0.70 : 0.40),
          strokeWidth: major ? 1.5 : 1,
          dashArray: major ? null : [3, 3],
          label: VerticalLineLabel(
            show: true,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(bottom: 2),
            style: TextStyle(
              color: solGreen.withValues(alpha: major ? 0.95 : 0.65),
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
            labelResolver: (_) => major ? 'M' : 'm',
          ),
        ));
      }

      addSol(sol.major1, true);
      addSol(sol.major2, true);
      addSol(sol.minor1, false);
      addSol(sol.minor2, false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Touch readout — shown while dragging, stable height to avoid jump
        SizedBox(
          height: 22,
          child: _touchX != null
              ? Center(
                  child: Text(
                    '${_fmtX(_touchX!)}  ·  ${_touchY!.toStringAsFixed(2)} ${widget.metric ? 'm' : 'ft'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        ),
        SizedBox(
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
                  horizontalInterval: widget.metric ? 0.5 : 2,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    final spot = response?.lineBarSpots?.firstOrNull;
                    setState(() {
                      if (spot != null &&
                          event is! FlPanEndEvent &&
                          event is! FlTapUpEvent &&
                          event is! FlLongPressEnd) {
                        _touchX = spot.x;
                        _touchY = spot.y;
                      } else if (event is FlPanEndEvent ||
                          event is FlTapUpEvent ||
                          event is FlLongPressEnd) {
                        _touchX = null;
                        _touchY = null;
                      }
                    });
                  },
                  getTouchedSpotIndicator: (_, indexes) => indexes
                      .map((_) => const TouchedSpotIndicatorData(
                            FlLine(color: Colors.transparent),
                            FlDotData(show: false),
                          ))
                      .toList(),
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (_) => [],
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(widget.metric ? 1 : 0),
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 10),
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
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                extraLinesData: ExtraLinesData(verticalLines: verticalLines),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: kCyan,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) {
                        return widget.hilo.any((p) =>
                            (p.time.hour + p.time.minute / 60 - spot.x).abs() <
                            0.3);
                      },
                      getDotPainter: (spot, _, __, ___) {
                        final isHigh = widget.hilo.any((p) =>
                            p.type == 'H' &&
                            (p.time.hour + p.time.minute / 60 - spot.x).abs() <
                                0.3);
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
                      color: kCyan.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _axisLabel(String t) =>
      Text(t, style: const TextStyle(color: Colors.white38, fontSize: 10));
}
