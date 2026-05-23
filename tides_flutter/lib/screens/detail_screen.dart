import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
import '../providers/detail_provider.dart';
import '../providers/favorites_provider.dart';
import '../widgets/conditions_card.dart';
import '../widgets/tide_chart.dart';
import '../services/noaa_api.dart' show fmtHhmm;
import '../theme.dart';
import 'about_screen.dart';

final _dayFmt = DateFormat('EEEE, MMM d, yyyy');
final _timeFmt2 = DateFormat('h:mm a');

class DetailScreen extends ConsumerWidget {
  final Station station;
  const DetailScreen({super.key, required this.station});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tideAsync = ref.watch(tideDataProvider);
    final isFav = ref.watch(favoritesProvider).any((s) => s.id == station.id);
    final date = ref.watch(selectedDateProvider);
    final weekAsync = ref.watch(weekDataProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        foregroundColor: Colors.white,
        title: Text(station.name.toUpperCase(),
            style: const TextStyle(color: kCyan, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
            child: const Text('Ref', style: TextStyle(color: kCyan)),
          ),
        ],
      ),
      body: Column(
        children: [
          _DateNav(date: date),
          _ViewToggle(),
          Expanded(
            child: tideAsync.when(
              data: (data) => data == null
                  ? const Center(
                      child: Text('No data', style: TextStyle(color: Colors.white54)))
                  : _TodayView(data: data, station: station),
              loading: () => const Center(
                  child: CircularProgressIndicator(color: kCyan)),
              error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: Colors.red))),
            ),
          ),
          if (!isFav)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.star_outline, size: 18),
                  label: const Text('Save to Favorites'),
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).add(station),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.star, size: 18, color: kCyan),
                  label: const Text('Remove from Favorites',
                      style: TextStyle(color: kCyan)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kCyan)),
                  onPressed: () => ref
                      .read(favoritesProvider.notifier)
                      .remove(station.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // simple bool provider for today/week toggle
    return const SizedBox.shrink(); // TODO: add SegmentedButton Today/Week
  }
}

class _DateNav extends ConsumerWidget {
  final DateTime date;
  const _DateNav({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final isToday = date == todayOnly;

    return Container(
      color: kNavyLight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: kCyan),
            onPressed: () => ref
                .read(selectedDateProvider.notifier)
                .state = date.subtract(const Duration(days: 1)),
          ),
          Expanded(
            child: Center(
              child: Text(
                isToday ? 'Today' : _dayFmt.format(date),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: kCyan),
            onPressed: () => ref
                .read(selectedDateProvider.notifier)
                .state = date.add(const Duration(days: 1)),
          ),
        ],
      ),
    );
  }
}

class _TodayView extends StatelessWidget {
  final TideData data;
  final Station station;
  const _TodayView({required this.data, required this.station});

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('Station ${station.id}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          ConditionsCard(c: data.conditions),
          if (data.nws != null) _NwsCard(nws: data.nws!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(children: [
              const Text('TIDE CHART',
                  style: TextStyle(
                      color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              const Spacer(),
              _legend(kHighTide, 'High'),
              const SizedBox(width: 12),
              _legend(kLowTide, 'Low'),
            ]),
          ),
          TideChart(
              hourly: data.hourly, hilo: data.hilo, isToday: data.isToday),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('HIGH / LOW TIDES',
                style: TextStyle(color: kCyan, fontSize: 11, letterSpacing: 1.5)),
          ),
          ...data.hilo.map(_hiloTile),
          _SolunarCard(data: data),
          _SunMoonCard(data: data),
          _FishingCard(data: data),
          const SizedBox(height: 8),
        ],
      );

  Widget _legend(Color c, String label) => Row(children: [
        Container(
            width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ]);

  Widget _hiloTile(TidePrediction p) {
    final isHigh = p.type == 'H';
    return ListTile(
      dense: true,
      leading: Icon(
        isHigh ? Icons.arrow_upward : Icons.arrow_downward,
        color: isHigh ? kHighTide : kLowTide,
        size: 18,
      ),
      title: Text(
        _timeFmt2.format(p.time),
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      trailing: Text(
        '${p.height >= 0 ? '+' : ''}${p.height.toStringAsFixed(2)} ft',
        style: TextStyle(
            color: isHigh ? kHighTide : kLowTide,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _NwsCard extends StatelessWidget {
  final NwsForecast nws;
  const _NwsCard({required this.nws});

  @override
  Widget build(BuildContext context) => Card(
        color: kCardBg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NWS',
                  style: TextStyle(color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              Text(
                '${nws.condition}  ·  ${nws.temp}°F  ·  Rain ${nws.rainPct}%',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (nws.windSpeed.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Wind ${nws.windDir} ${nws.windSpeed}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
        ),
      );
}

class _SolunarCard extends StatelessWidget {
  final TideData data;
  const _SolunarCard({required this.data});

  @override
  Widget build(BuildContext context) => Card(
        color: kCardBg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SOLUNAR',
                  style: TextStyle(color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _sol('Major 1', data.solunar.major1),
                  _sol('Major 2', data.solunar.major2),
                  _sol('Minor 1', data.solunar.minor1),
                  _sol('Minor 2', data.solunar.minor2),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _sol(String label, double h) => Expanded(
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 2),
            Text(fmtHhmm(h),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );
}

class _SunMoonCard extends StatelessWidget {
  final TideData data;
  const _SunMoonCard({required this.data});

  @override
  Widget build(BuildContext context) => Card(
        color: kCardBg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SUN',
                        style: TextStyle(
                            color: kCyan, fontSize: 11, letterSpacing: 1.5)),
                    const SizedBox(height: 6),
                    _row('Rise', data.sun.sunrise),
                    _row('Set', data.sun.sunset),
                    _row('Golden', data.sun.golden),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MOON',
                        style: TextStyle(
                            color: kCyan, fontSize: 11, letterSpacing: 1.5)),
                    const SizedBox(height: 6),
                    _row('Phase', data.moon.phase),
                    _row('Illumination', '${data.moon.pct}%'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Text('$label  ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );
}

class _FishingCard extends StatelessWidget {
  final TideData data;
  const _FishingCard({required this.data});

  @override
  Widget build(BuildContext context) {
    if (!data.isToday) return const SizedBox.shrink();
    final stars = '★' * data.fishing.stars + '☆' * (5 - data.fishing.stars);
    return Card(
      color: kCardBg,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Text('FISHING  ',
                style: TextStyle(color: kCyan, fontSize: 11, letterSpacing: 1.5)),
            Text(stars, style: const TextStyle(color: Colors.amber, fontSize: 16)),
            const SizedBox(width: 8),
            Text(data.fishing.label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
