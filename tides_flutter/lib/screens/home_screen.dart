import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../providers/search_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/detail_provider.dart';
import '../services/location_service.dart';
import '../services/noaa_api.dart';
import '../widgets/wave_header.dart';
import '../widgets/station_tile.dart';
import '../theme.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();
  bool _locating = false;
  String? _locMsg;
  List<Station>? _nearbyStations;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _locateMe() async {
    setState(() { _locating = true; _locMsg = null; _nearbyStations = null; });
    final loc = await getLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() { _locating = false; _locMsg = 'Could not detect location — search manually'; });
      return;
    }
    final (lat, lon, city) = loc;
    final stations = await nearestStations(lat, lon);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _locMsg = 'Near ${city[0].toUpperCase()}${city.substring(1)}';
      _nearbyStations = stations;
    });
    _ctrl.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  void _openStation(Station s) {
    ref.read(selectedStationProvider.notifier).state = s;
    final now = DateTime.now();
    ref.read(selectedDateProvider.notifier).state =
        DateTime(now.year, now.month, now.day);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(station: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(searchResultsProvider);
    final favorites = ref.watch(favoritesProvider);
    final query = ref.watch(searchQueryProvider);

    final showSearch = query.length >= 2;
    final showNearby = _nearbyStations != null && !showSearch;
    final showFavs = favorites.isNotEmpty && !showSearch && !showNearby;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        automaticallyImplyLeading: false,
        title: const Text('~ TIDES',
            style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: kCyan),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          WaveHeader(locationName: _locMsg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Search by city, station name, or state…',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) =>
                        ref.read(searchQueryProvider.notifier).state = v,
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _locating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: kNavy, strokeWidth: 2))
                      : const Icon(Icons.search, size: 16),
                  label: const Text('Search'),
                  onPressed: _locating ? null : () {},
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _locating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: kCyan, strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16, color: kCyan),
                label: Text(_locating ? 'Detecting location…' : 'Use My Location',
                    style: const TextStyle(color: kCyan)),
                style:
                    OutlinedButton.styleFrom(side: const BorderSide(color: kCyan)),
                onPressed: _locating ? null : _locateMe,
              ),
            ),
          ),
          if (_locMsg != null && !_locating && _nearbyStations == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_locMsg!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: showSearch
                ? searchAsync.when(
                    data: (results) => results.isEmpty
                        ? const Center(
                            child: Text('No stations found.',
                                style: TextStyle(color: Colors.white54)))
                        : _StationList(
                            label:
                                'Results for "${_ctrl.text}"',
                            stations: results,
                            onTap: _openStation,
                            favorites: favorites,
                          ),
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: kCyan)),
                    error: (e, _) => Center(
                        child: Text('$e',
                            style: const TextStyle(color: Colors.red))),
                  )
                : showNearby
                    ? _StationList(
                        label: _locMsg ?? 'Nearby Stations',
                        stations: _nearbyStations!,
                        onTap: _openStation,
                        favorites: favorites,
                      )
                    : showFavs
                        ? _StationList(
                            label: 'Favorites',
                            stations: favorites,
                            onTap: _openStation,
                            favorites: favorites,
                          )
                        : const Center(
                            child: Text('Search for a station above to get started.',
                                style: TextStyle(color: Colors.white54))),
          ),
        ],
      ),
    );
  }
}

class _StationList extends StatelessWidget {
  final String label;
  final List<Station> stations;
  final void Function(Station) onTap;
  final List<Station> favorites;

  const _StationList({
    required this.label,
    required this.stations,
    required this.onTap,
    required this.favorites,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              '${stations.length} station(s) found\n'
              'Results for "$label"',
              style: const TextStyle(color: kCyan, fontSize: 12),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: stations.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Colors.white10, height: 1),
              itemBuilder: (_, i) => StationTile(
                station: stations[i],
                isFavorite: favorites.any((f) => f.id == stations[i].id),
                onTap: () => onTap(stations[i]),
              ),
            ),
          ),
        ],
      );
}
