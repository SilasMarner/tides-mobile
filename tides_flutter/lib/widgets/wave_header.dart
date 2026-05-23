import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class WaveHeader extends StatefulWidget {
  final String? locationName;
  const WaveHeader({super.key, this.locationName});

  @override
  State<WaveHeader> createState() => _WaveHeaderState();
}

class _WaveHeaderState extends State<WaveHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _WavePainter(_ctrl.value),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '~ TIDES',
                    style: TextStyle(
                      color: kCyan,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Live NOAA Conditions',
                    style: TextStyle(color: kCyanLight, fontSize: 13),
                  ),
                  if (widget.locationName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.locationName!,
                      style: const TextStyle(color: kCyan, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _WavePainter extends CustomPainter {
  final double phase;
  _WavePainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final waves = [
      (kCyan.withOpacity(0.25), 0.0, 18.0, size.height * 0.72),
      (kCyan.withOpacity(0.18), 0.4, 14.0, size.height * 0.78),
      (kCyanLight.withOpacity(0.12), 0.7, 10.0, size.height * 0.82),
    ];

    for (final (color, offset, amp, baseline) in waves) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final path = Path();
      path.moveTo(0, baseline);
      for (var x = 0.0; x <= size.width; x++) {
        final y = baseline +
            amp * sin((x / size.width * 2 * pi) + (phase + offset) * 2 * pi);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.phase != phase;
}
