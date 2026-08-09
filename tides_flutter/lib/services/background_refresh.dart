import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/station.dart';
import 'noaa_api.dart';

// Keeps the favourites' tide cache warm in the background so a NOAA datagetter
// outage (or simply opening the app offline) still shows tide curves. Twice a
// day WorkManager wakes a background isolate that fetches one week of hi/lo
// predictions per favourite and persists a tides-only entry per day to the same
// disk cache the UI rehydrates on launch (see [warmTidesOnly]), and refreshes
// each favourite's year-long season cache once it starts aging out (see
// [warmSeason]) — the season cache is what actually survives a long stretch
// with no connectivity, since it doesn't depend on this job firing on time.

const _taskName = 'opentides.tideCacheRefresh';
const _uniqueName = 'opentides-tide-cache-refresh';

// The key the favourites provider persists its station list under.
const _favoritesKey = 'favorites';

/// WorkManager's background entry point. Must be a top-level function and kept
/// by the AOT compiler, hence the [pragma]. Runs in its own isolate with no
/// access to the UI isolate's memory — it only shares SharedPreferences.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await _refreshFavouritesCache();
    } catch (_) {
      // Best-effort: swallow so WorkManager doesn't treat it as a hard failure
      // and back off aggressively. The cache simply stays as it was.
    }
    return true;
  });
}

Future<void> _refreshFavouritesCache() async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(_favoritesKey);
  if (raw == null || raw.isEmpty) return;

  final List<dynamic> list;
  try {
    list = jsonDecode(raw) as List<dynamic>;
  } catch (_) {
    return;
  }

  for (final entry in list) {
    try {
      final station = Station.fromJson(entry as Map<String, dynamic>);
      await warmTidesOnly(station);
      await warmSeason(station);
    } catch (_) {
      // Skip a malformed favourite or a station whose fetch failed; keep going.
    }
  }
}

/// Initialises WorkManager and (re)registers the periodic tide-cache refresh.
/// Safe to call on every cold start: registering with the same unique name and
/// [ExistingWorkPolicy.keep] is idempotent and won't stack duplicate work.
Future<void> initBackgroundRefresh() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(hours: 12),
    // Don't fire the instant the app first launches — let the foreground warm
    // the cache itself; the background job is for keeping it fresh thereafter.
    initialDelay: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 30),
  );
}

/// Runs the cache refresh once, immediately, as a one-off background task.
/// Used to validate the path during QA without waiting for the 12 h cadence.
Future<void> triggerRefreshNow() async {
  await Workmanager().registerOneOffTask(
    'opentides-tide-cache-refresh-now',
    _taskName,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
