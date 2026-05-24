import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
            const SizedBox(height: 2),
            const Text('Built with Flutter',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const Divider(color: Colors.white12, height: 32),

            // Features
            const Text('Features',
                style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ..._features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(color: kCyan, fontSize: 13)),
                      Expanded(
                        child: Text(f,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ),
                    ],
                  ),
                )),
            const Divider(color: Colors.white12, height: 32),

            // Developer
            const Text('Developer',
                style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Matt Bettinger',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 2),
            const Text('tides-mobile.human695@passmail.com',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            const Text('github.com/SilasMarner/tides-mobile',
                style: TextStyle(color: kCyan, fontSize: 12)),
            const Divider(color: Colors.white12, height: 32),

            // Thanks
            const Text('Thanks',
                style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              color: kCardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'A huge thank you to everyone who helped make this app possible:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  _thanksRow(Icons.favorite, kCyan,
                      'Shelly', 'My wife — for her patience, encouragement, and support throughout this project.'),
                  const SizedBox(height: 12),
                  _thanksRow(Icons.people, Colors.white54,
                      'Friends & testers', 'Everyone who offered suggestions and took time to put this through its paces.'),
                  const SizedBox(height: 12),
                  _thanksRow(Icons.set_meal, Colors.white54,
                      'The fishing community', 'For the enthusiasm, real-world feedback, and keeping the love of fishing alive.'),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse('https://www.dosfrio.com'),
                        mode: LaunchMode.externalApplication),
                    child: _thanksRow(Icons.forum, kCyan,
                        'dosfrio.com', 'A fantastic online fishing community. Thanks for being such a welcoming, knowledgeable group of folks.',
                        linkLabel: 'Visit dosfrio.com'),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse('https://www.montyweeks.com'),
                        mode: LaunchMode.externalApplication),
                    child: _thanksRow(Icons.build, kCyan,
                        'Monty Weeks', 'A special thank you to Monty for keeping the dosfrio.com board running and maintaining it for all of us to enjoy. Check out his custom stainless steel art and knives — handcrafted in Texas!',
                        linkLabel: 'montyweeks.com'),
                  ),
                ],
              ),
            ),
          ),
            const Divider(color: Colors.white12, height: 32),

            // Credits
            const Text('Open Source Software & Data Sources',
                style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._credits.map(_creditTile),
          ],
        ),
      );

  static Widget _thanksRow(IconData icon, Color iconColor, String name, String text,
      {String? linkLabel}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                if (linkLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(linkLabel,
                      style: const TextStyle(color: kCyan, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      );

  static const _features = [
    'Live 24-hour tide charts with hi/lo markers and current-time indicator',
    'All ~3,450 NOAA tide stations — search by city, name, or state',
    'Real-time conditions: air & water temp, pressure, water level, salinity',
    'Salinity displayed for stations with a sensor (ppt / PSU)',
    'NWS 7-day forecast per station — tap to expand full daily detail',
    'Week view: hi/lo tides for 7 days with NWS forecast per day',
    'Solunar tables: major & minor feeding periods',
    'Sun & moon: sunrise, sunset, golden hour, phase, illumination',
    'Fishing rating (1–5 stars) based on tides, solunar timing, and wind',
    'Favorites and GPS-based nearest stations',
    'Notifications for tide changes, solunar majors, and best fishing days',
  ];

  static const _credits = [
    ('Flutter', 'BSD 3-Clause', 'flutter.dev'),
    ('Dart', 'BSD 3-Clause', 'dart.dev'),
    ('fl_chart', 'MIT License', 'github.com/imaNNeo/fl_chart'),
    ('Riverpod', 'MIT License', 'riverpod.dev'),
    ('Dio', 'MIT License', 'pub.dev/packages/dio'),
    ('Geolocator', 'MIT License', 'pub.dev/packages/geolocator'),
    ('intl', 'BSD 3-Clause', 'pub.dev/packages/intl'),
    ('shared_preferences', 'BSD 3-Clause', 'pub.dev/packages/shared_preferences'),
    ('url_launcher', 'BSD 3-Clause', 'pub.dev/packages/url_launcher'),
    ('NOAA CO-OPS API', 'Public Domain', 'tidesandcurrents.noaa.gov'),
    ('NWS API', 'Public Domain', 'weather.gov'),
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
