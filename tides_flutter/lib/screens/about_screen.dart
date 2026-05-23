import 'package:flutter/material.dart';
import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('About'),
          backgroundColor: kNavyLight,
          foregroundColor: kCyan,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('~ TIDES',
                style: TextStyle(
                    color: kCyan, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Version 2.0  ·  Live NOAA tide data for Android',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const Divider(color: Colors.white12, height: 32),
            const Text('Developer',
                style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Matt Bettinger',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 2),
            const Text('tides-mobile.human695@passmail.com',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Divider(color: Colors.white12, height: 32),
            const Text('Open Source Software & Data Sources',
                style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._credits.map(_creditTile),
          ],
        ),
      );

  static const _credits = [
    ('Flutter', 'BSD 3-Clause', 'flutter.dev'),
    ('Dart', 'BSD 3-Clause', 'dart.dev'),
    ('fl_chart', 'MIT License', 'github.com/imaNNeo/fl_chart'),
    ('Riverpod', 'MIT License', 'riverpod.dev'),
    ('Dio', 'MIT License', 'pub.dev/packages/dio'),
    ('Geolocator', 'MIT License', 'pub.dev/packages/geolocator'),
    ('NOAA CO-OPS API', 'Public Domain', 'tidesandcurrents.noaa.gov'),
    ('NWS API', 'Public Domain', 'weather.gov/documentation/services-web-api'),
  ];

  Widget _creditTile((String, String, String) c) => Card(
        color: kCardBg,
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.$1,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${c.$2}  ·  ${c.$3}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      );
}
