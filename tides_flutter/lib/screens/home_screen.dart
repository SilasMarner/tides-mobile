import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import '../models/station.dart';
import '../providers/search_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/detail_provider.dart';
import '../services/location_service.dart';
import '../services/noaa_api.dart';
import '../providers/capabilities_provider.dart';
import '../widgets/wave_header.dart';
import '../widgets/station_tile.dart';
import '../theme.dart';
import 'about_screen.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      // Warm the cache for favorites as soon as they load from disk.
      ref.listenManual(favoritesProvider, (_, favorites) {
        if (favorites.isNotEmpty) schedulePrefetch(favorites);
      }, fireImmediately: true);
    });
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      if (!mounted) return;
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        InAppUpdate.installUpdateListener.listen((status) {
          if (status == InstallStatus.downloaded && mounted) {
            _showUpdateBanner();
          }
        });
      }
    } catch (_) {
      // Not a Play Store build, no network, or update API unavailable — ignore
    }
  }

  void _showUpdateBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: kNavyLight,
        content: const Text(
          'Update downloaded and ready to install.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              InAppUpdate.completeFlexibleUpdate();
            },
            child: const Text('RESTART', style: TextStyle(color: kCyan)),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('LATER',
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

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

  void _toggleFavorite(Station s) {
    final isFav = ref.read(favoritesProvider).any((f) => f.id == s.id);
    if (isFav) {
      ref.read(favoritesProvider.notifier).remove(s.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${s.name} removed from favorites'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      ref.read(favoritesProvider.notifier).add(s);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${s.name} added to favorites'),
        duration: const Duration(seconds: 2),
      ));
    }
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
    final capsMap = ref.watch(stationCapabilitiesProvider).valueOrNull;

    final showSearch = query.length >= 2;
    final showNearby = _nearbyStations != null && !showSearch;
    final showFavs = favorites.isNotEmpty && !showSearch && !showNearby;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyLight,
        automaticallyImplyLeading: false,
        title: const Text('~ OpenTides',
            style: TextStyle(color: kCyan, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: kCyan),
            tooltip: 'About',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: kCyan),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      // Cap content width so large screens (tablets) show a centered column
      // instead of stretching phone-width controls edge to edge.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
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
                            label: 'Results for "${_ctrl.text}"',
                            stations: results,
                            onTap: _openStation,
                            onLongPress: _toggleFavorite,
                            favorites: favorites,
                            capsMap: capsMap,
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
                        onLongPress: _toggleFavorite,
                        favorites: favorites,
                        capsMap: capsMap,
                      )
                    : showFavs
                        ? _StationList(
                            label: 'Favorites',
                            stations: favorites,
                            onTap: _openStation,
                            onLongPress: _toggleFavorite,
                            favorites: favorites,
                            capsMap: capsMap,
                            onReorder: (o, n) => ref
                                .read(favoritesProvider.notifier)
                                .reorder(o, n),
                          )
                        : const Center(
                            child: Text('Search for a station above to get started.',
                                style: TextStyle(color: Colors.white54))),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _StationList extends StatelessWidget {
  final String label;
  final List<Station> stations;
  final void Function(Station) onTap;
  final void Function(Station) onLongPress;
  final List<Station> favorites;
  final Map<String, Set<String>>? capsMap;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const _StationList({
    required this.label,
    required this.stations,
    required this.onTap,
    required this.onLongPress,
    required this.favorites,
    this.capsMap,
    this.onReorder,
  });

  void _showLegend(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kNavyLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sensor availability',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Icons shown next to stations that have the live sensor.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...kStationBadges.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(children: [
                    Icon(b.icon, size: 18, color: kCyan),
                    const SizedBox(width: 14),
                    Text(b.label,
                        style: const TextStyle(color: Colors.white70)),
                  ]),
                )),
            const SizedBox(height: 4),
            const Text(
              'Stations without icons still have full tide predictions.',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${stations.length} station(s) found\n'
                    'Results for "$label"',
                    style: const TextStyle(color: kCyan, fontSize: 12),
                  ),
                ),
                if (capsMap != null)
                  Tooltip(
                    message: 'Sensor legend',
                    child: IconButton(
                      icon: const Icon(Icons.info, size: 18, color: kCyan),
                      onPressed: () => _showLegend(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: onReorder != null
                ? ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: stations.length,
                    // onReorder is still the required, documented callback; the
                    // onReorderItem replacement is too new to rely on here.
                    // ignore: deprecated_member_use
                    onReorder: onReorder!,
                    itemBuilder: (_, i) => StationTile(
                      key: ValueKey(stations[i].id),
                      station: stations[i],
                      isFavorite:
                          favorites.any((f) => f.id == stations[i].id),
                      onTap: () => onTap(stations[i]),
                      onLongPress: () => onLongPress(stations[i]),
                      caps: capsMap?[stations[i].id],
                      dragHandle: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle,
                              color: Colors.white38),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: stations.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) => StationTile(
                      station: stations[i],
                      isFavorite:
                          favorites.any((f) => f.id == stations[i].id),
                      onTap: () => onTap(stations[i]),
                      onLongPress: () => onLongPress(stations[i]),
                      caps: capsMap?[stations[i].id],
                    ),
                  ),
          ),
        ],
      );
}
