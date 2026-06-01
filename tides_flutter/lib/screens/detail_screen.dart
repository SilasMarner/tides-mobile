import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
import '../providers/detail_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/units_provider.dart';
import '../services/notification_service.dart';
import '../utils/unit_format.dart';
import '../widgets/conditions_card.dart';
import '../widgets/tide_chart.dart';
import '../services/noaa_api.dart' show fmtHhmm, WaveData;
import '../theme.dart';
import 'about_screen.dart';
import 'wind_map_screen.dart';
import 'salinity_map_screen.dart';

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
    final showWeek = ref.watch(showWeekProvider);
    final notifPrefs = ref.watch(notificationPrefsProvider);
    final metric = ref.watch(unitsProvider);
    final notifEnabled = notifPrefs.enabled &&
        notifPrefs.stations.contains(station.id);

    // Schedule notifications whenever today's data loads for this station
    ref.listen(tideDataProvider, (_, next) {
      next.whenData((data) {
        if (data != null && data.isToday && notifEnabled) {
          NotificationService.scheduleForStation(
              station.id, station.name, data, notifPrefs,
              metric: ref.read(unitsProvider));
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        foregroundColor: Colors.white,
        title: Text(station.name.toUpperCase(),
            style: const TextStyle(color: kCyan, fontSize: 14)),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.star : Icons.star_outline,
              color: isFav ? kCyan : Colors.white38,
            ),
            tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () {
              if (isFav) {
                ref.read(favoritesProvider.notifier).remove(station.id);
              } else {
                ref.read(favoritesProvider.notifier).add(station);
              }
            },
          ),
          IconButton(
            icon: Icon(
              notifEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: notifEnabled ? kCyan : Colors.white38,
            ),
            tooltip: notifEnabled ? 'Notifications on' : 'Notifications off',
            onPressed: () {
              if (!notifPrefs.enabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enable notifications in Settings first'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              ref
                  .read(notificationPrefsProvider.notifier)
                  .toggleStation(station.id);
            },
          ),
          IconButton(
            icon: const Icon(Icons.air, color: kCyan),
            tooltip: 'Wind Map',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WindMapScreen(
                  lat: station.lat,
                  lon: station.lon,
                  stationName: station.name,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.water_drop, color: kCyan),
            tooltip: 'Salinity Map',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SalinityMapScreen(
                  lat: station.lat,
                  lon: station.lon,
                  stationName: station.name,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: kCyan),
            color: kNavyLight,
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'refresh') {
                ref.invalidate(tideDataProvider);
                ref.invalidate(weekDataProvider);
              } else if (v == 'about') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync, color: kCyan),
                  title: Text('Refresh', style: TextStyle(color: Colors.white)),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline, color: kCyan),
                  title: Text('About', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _DateNav(date: date),
          _ViewToggle(),
          Expanded(
            child: showWeek
                ? weekAsync.when(
                    data: (preds) => _WeekView(
                      predictions: preds,
                      nws: tideAsync.valueOrNull?.nws,
                      metric: metric,
                    ),
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: kCyan)),
                    error: (e, _) => Center(
                        child: Text('Error: $e',
                            style: const TextStyle(color: Colors.red))),
                  )
                : tideAsync.when(
                    data: (data) => data == null
                        ? const Center(
                            child: Text('No data',
                                style: TextStyle(color: Colors.white54)))
                        : _TodayView(
                            data: data, station: station, metric: metric),
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: kCyan)),
                    error: (e, _) => Center(
                        child: Text('Error: $e',
                            style: const TextStyle(color: Colors.red))),
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
    final showWeek = ref.watch(showWeekProvider);
    return Container(
      color: kNavyLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SegmentedButton<bool>(
        style: SegmentedButton.styleFrom(
          backgroundColor: kNavy,
          foregroundColor: Colors.white54,
          selectedForegroundColor: kCyan,
          selectedBackgroundColor: kNavyLight,
          side: const BorderSide(color: kCyan, width: 1),
        ),
        segments: const [
          ButtonSegment(value: false, label: Text('TODAY')),
          ButtonSegment(value: true, label: Text('WEEK')),
        ],
        selected: {showWeek},
        onSelectionChanged: (s) =>
            ref.read(showWeekProvider.notifier).state = s.first,
      ),
    );
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
  final bool metric;
  const _TodayView(
      {required this.data, required this.station, required this.metric});

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full station name — the app-bar title truncates when there
                // are several toolbar actions, so show it in full here.
                Text(station.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Station ${station.id}',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          ConditionsCard(c: data.conditions),
          if (data.waves != null) _WaveCard(waves: data.waves!, metric: metric),
          if (data.nws != null) _NwsCard(nws: data.nws!, metric: metric),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(children: [
              const Text('TIDE CHART',
                  style: TextStyle(
                      color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              const Spacer(),
              _legend(kHighTide, 'High'),
              const SizedBox(width: 10),
              _legend(kLowTide, 'Low'),
              const SizedBox(width: 10),
              _legend(const Color(0xFF66BB6A), 'Solunar'),
            ]),
          ),
          TideChart(
              hourly: data.hourly,
              hilo: data.hilo,
              isToday: data.isToday,
              metric: metric,
              solunar: data.solunar),
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
        fmtTideHeight(p.height, metric),
        style: TextStyle(
            color: isHigh ? kHighTide : kLowTide,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _NwsCard extends StatefulWidget {
  final NwsForecast nws;
  final bool metric;
  const _NwsCard({required this.nws, required this.metric});

  @override
  State<_NwsCard> createState() => _NwsCardState();
}

class _NwsCardState extends State<_NwsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final nws = widget.nws;
    return Card(
      color: kCardBg,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: nws.periods.isNotEmpty
            ? () => setState(() => _expanded = !_expanded)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  const Text('NWS',
                      style: TextStyle(
                          color: kCyan, fontSize: 11, letterSpacing: 1.5)),
                  const Spacer(),
                  if (nws.periods.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white38,
                      size: 18,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Current conditions summary
              Text(
                '${nws.condition}  ·  ${fmtTempInt(nws.temp, widget.metric)}  ·  Rain ${nws.rainPct}%',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (nws.windSpeed.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Wind ${nws.windDir} ${fmtWindString(nws.windSpeed, widget.metric)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              // Expanded: full forecast periods
              if (_expanded && nws.periods.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(color: Colors.white12, height: 1),
                ...nws.periods.map((p) => Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                                color: kCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          if (p.temp > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${fmtTempInt(p.temp, widget.metric)}  ·  ${p.shortForecast}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 3),
                          Text(
                            p.detail,
                            style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _moonEmoji(data.moon.phase),
                          style: const TextStyle(fontSize: 36),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Phase', data.moon.phase),
                              _row('Lit', '${data.moon.pct}%'),
                            ],
                          ),
                        ),
                      ],
                    ),
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
            Flexible(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
      );

  String _moonEmoji(String phase) {
    switch (phase) {
      case 'New Moon':        return '🌑';
      case 'Waxing Crescent': return '🌒';
      case 'First Quarter':   return '🌓';
      case 'Waxing Gibbous':  return '🌔';
      case 'Full Moon':       return '🌕';
      case 'Waning Gibbous':  return '🌖';
      case 'Last Quarter':    return '🌗';
      case 'Waning Crescent': return '🌘';
      default:                return '🌙';
    }
  }
}

final _weekDayFmt = DateFormat('EEE, MMM d');
final _weekTimeFmt = DateFormat('h:mm a');

class _WeekView extends StatefulWidget {
  final List<TidePrediction> predictions;
  final NwsForecast? nws;
  final bool metric;
  const _WeekView({required this.predictions, this.nws, required this.metric});

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  final Set<DateTime> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final predictions = widget.predictions;
    final nws = widget.nws;
    if (predictions.isEmpty) {
      return const Center(
        child: Text('No week data', style: TextStyle(color: Colors.white38)),
      );
    }

    // Group NWS periods by day name (skip "Night" periods for the day header)
    final Map<String, NwsPeriod> nwsByDay = {};
    for (final p in (nws?.periods ?? [])) {
      // Store daytime periods keyed by their name (e.g. "Monday")
      if (!p.name.toLowerCase().contains('night') &&
          !p.name.toLowerCase().contains('tonight')) {
        nwsByDay[p.name.toLowerCase()] = p;
      }
    }
    // Group tide predictions by calendar date
    final Map<DateTime, List<TidePrediction>> byDay = {};
    for (final p in predictions) {
      final day = DateTime(p.time.year, p.time.month, p.time.day);
      byDay.putIfAbsent(day, () => []).add(p);
    }
    final days = byDay.keys.toList()..sort();

    final dayNameFmt = DateFormat('EEEE'); // full day name for NWS lookup

    return ListView.builder(
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day = days[i];
        final preds = byDay[day]!;
        final today = DateTime.now();
        final isToday = day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;

        // Find matching NWS period for this day
        final dayName = isToday ? 'today' : dayNameFmt.format(day).toLowerCase();
        final nwsPeriod = nwsByDay[dayName];

        final isExpanded = _expanded.contains(day);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: nwsPeriod != null
                  ? () => setState(() {
                        if (isExpanded) {
                          _expanded.remove(day);
                        } else {
                          _expanded.add(day);
                        }
                      })
                  : null,
              child: Container(
                color: kCardBg,
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday
                          ? 'TODAY — ${_weekDayFmt.format(day)}'
                          : _weekDayFmt.format(day).toUpperCase(),
                      style: TextStyle(
                        color: isToday ? kCyan : Colors.white70,
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (nwsPeriod != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Text(
                          '${fmtTempInt(nwsPeriod.temp, widget.metric)}  ',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: Text(
                            nwsPeriod.shortForecast,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.white38,
                          size: 18,
                        ),
                      ]),
                      if (isExpanded) ...[
                        const SizedBox(height: 6),
                        Text(
                          nwsPeriod.detail,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            ...preds.map((p) {
              final isHigh = p.type == 'H';
              return ListTile(
                dense: true,
                leading: Icon(
                  isHigh ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isHigh ? kHighTide : kLowTide,
                  size: 18,
                ),
                title: Text(
                  _weekTimeFmt.format(p.time),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                trailing: Text(
                  fmtTideHeight(p.height, widget.metric),
                  style: TextStyle(
                    color: isHigh ? kHighTide : kLowTide,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
            const Divider(color: Colors.white10, height: 1),
          ],
        );
      },
    );
  }
}

class _WaveCard extends StatelessWidget {
  final WaveData waves;
  final bool metric;
  const _WaveCard({required this.waves, required this.metric});

  @override
  Widget build(BuildContext context) {
    final w = waves;
    return Card(
      color: kCardBg,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('WAVES',
                  style: TextStyle(color: kCyan, fontSize: 11, letterSpacing: 1.5)),
              const Spacer(),
              Text(
                w.source,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _cell('Wave Ht', fmtLen(w.waveHeight, metric)),
              _cell('Dom Period', w.domPeriod > 0 ? '${w.domPeriod.toStringAsFixed(0)} sec' : 'N/A'),
              _cell('Direction', w.waveDir ?? 'N/A'),
              const Expanded(child: SizedBox()),
            ]),
            if (w.swellHeight != null || w.windWaveHeight != null) ...[
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),
              if (w.swellHeight != null)
                _swellRow(
                  label: 'Swell',
                  height: w.swellHeight!,
                  period: w.swellPeriod,
                  dir: w.swellDir,
                ),
              if (w.windWaveHeight != null) ...[
                if (w.swellHeight != null) const SizedBox(height: 6),
                _swellRow(
                  label: 'Wind Sea',
                  height: w.windWaveHeight!,
                  period: w.windWavePeriod,
                  dir: null,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _swellRow({
    required String label,
    required double height,
    double? period,
    String? dir,
  }) =>
      Row(children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Text(fmtLen(height, metric),
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        if (period != null) ...[
          const Text('  ·  ', style: TextStyle(color: Colors.white24)),
          Text('${period.toStringAsFixed(0)} sec',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
        if (dir != null) ...[
          const Text('  ·  ', style: TextStyle(color: Colors.white24)),
          Text(dir, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ]);
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
