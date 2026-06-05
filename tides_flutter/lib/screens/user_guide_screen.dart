import 'package:flutter/material.dart';
import '../theme.dart';

/// A quick, scrollable user guide: what the app shows, where the data comes
/// from, how the fishing score is calculated, and how the alerts work.
class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('User Guide'),
          backgroundColor: kNavyLight,
          foregroundColor: kCyan,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text('How OpenTides works',
                style: TextStyle(
                    color: kCyan, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'A quick guide to reading the app, where the numbers come from, '
              'and how the fishing score and alerts are calculated. Everything '
              'is computed on your phone from free public data — no account, no '
              'tracking, no ads.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            ..._sections.map(_buildSection),
          ],
        ),
      );

  Widget _buildSection(_Section s) => Card(
        color: kCardBg,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(s.icon, color: kCyan, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.title,
                        style: const TextStyle(
                            color: kCyan,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...s.body.map((b) => b.startsWith('• ')
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(color: kCyan, fontSize: 13)),
                          Expanded(
                            child: Text(b.substring(2),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.45)),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(b,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.45)),
                    )),
            ],
          ),
        ),
      );

  static const _sections = <_Section>[
    _Section(
      Icons.public,
      'Where the data comes from',
      [
        'Every figure is pulled live from official, free sources and combined on your device:',
        '• Tides — NOAA CO-OPS (tidesandcurrents.noaa.gov): official predictions and real-time water level, water temp, air temp, wind, barometric pressure, and salinity from ~3,450 stations.',
        '• Weather & forecast — the U.S. National Weather Service (weather.gov) for the per-station 7-day forecast.',
        '• Waves & marine — Open-Meteo Marine for wave height, swell, and period at the station’s location.',
        '• Sun, moon & solunar — calculated on the phone from the station’s latitude/longitude and date (no network needed).',
      ],
    ),
    _Section(
      Icons.show_chart,
      'Reading the tide chart',
      [
        'The curve is the predicted water height across the day. Dots mark the high (light) and low (dark) tides, and the amber vertical line is the current time. Green bands are solunar feeding periods.',
        'Use the TODAY / WEEK toggle and the < > arrows to move to any day. On future days the Conditions card switches to that day’s forecast (tagged “Forecast · midday”) since live sensor readings only exist for right now.',
      ],
    ),
    _Section(
      Icons.water,
      'Wind tide (water vs. predicted)',
      [
        'Under the Conditions card you may see a line like “Water 0.7 ft below predicted.” That is the wind tide: the difference between the live observed water level and the astronomical tide prediction.',
        'On the Texas coast it matters a lot: sustained north winds push water out of the bays and back-lakes (water runs below prediction), while south winds stack water in (above prediction). A big difference tells you the flats and marsh drains are unusually low or high right now.',
        'It only shows today, on stations that report a live water-level sensor.',
      ],
    ),
    _Section(
      Icons.set_meal,
      'How the fishing score is calculated',
      [
        'The 1–5 star rating is a quick read on how good the bite looks right now. Stars are earned from factors that line up in your favor:',
        '• Moving water — the tide’s rate of change vs. the day’s strongest movement. Fish feed on current, not slack water.',
        '• Solunar timing — being inside a major (or minor) feeding period.',
        '• Wind — lighter wind (under ~10–15 mph) scores higher; blown-out bays score lower.',
        '• Barometer — a falling pressure trend adds a point, since fish often feed ahead of a front.',
        'Future days use a simpler version based on how well the solunar majors line up with the day’s tide changes (the classic lunar-calendar method), since live wind and pressure aren’t known yet.',
        'Best Windows lists today’s top 2–3 time blocks where those factors stack up, and the movement line (e.g. “Incoming — strongest 2–4 PM”) tells you when the tide runs hardest.',
      ],
    ),
    _Section(
      Icons.brightness_3,
      'Solunar, sun & moon',
      [
        'Solunar theory ties fish (and game) activity to the moon’s position. Major periods (~2 hrs, moon overhead/underfoot) are the strongest; minor periods (~1 hr, moonrise/moonset) are secondary.',
        'The Sun/Moon card shows sunrise, sunset, golden hour, and the moon phase with percent illumination — dawn and dusk around a feeding period are prime.',
      ],
    ),
    _Section(
      Icons.notifications_active,
      'Alerts & notifications',
      [
        'Turn on notifications in Settings, then enable them per favorite station. Choose how far ahead to be warned (15/30/45/60 min). Available alerts:',
        '• High & Low Tide — a heads-up before each tide change.',
        '• Solunar Major Windows — before each major feeding period.',
        '• Best Fishing Days — one morning alert when today rates 4+ stars.',
        '• Pressure Drops — fires when the barometer is falling (a front approaching, often a strong pre-front bite). Sent once per day per station.',
        'Alerts are scheduled each time you open a station, so opening the app keeps them fresh. They run locally on your phone.',
      ],
    ),
    _Section(
      Icons.map,
      'Maps',
      [
        '• Weather map — animated Wind, Waves, Swell, Temperature, Pressure, and Clouds layers, plus a Rain timeline that flows NOAA radar (past 2 hrs) into an 18-hour forecast. Tap anywhere to read the value at that point.',
        '• Salinity map — NOAA NGOFS2 hourly surface-salinity loop for Gulf bays.',
        '• Sargassum map — NOAA’s daily coastal seaweed inundation risk.',
      ],
    ),
    _Section(
      Icons.tune,
      'Tips',
      [
        '• Switch between Standard (°F, mph, ft) and Metric in Settings.',
        '• Tap the star on a station to save it as a favorite; the home screen also finds the nearest stations by GPS.',
        '• “N/A” simply means that station has no sensor for that reading — tides and forecast still work.',
      ],
    ),
  ];
}

class _Section {
  final IconData icon;
  final String title;
  final List<String> body;
  const _Section(this.icon, this.title, this.body);
}
