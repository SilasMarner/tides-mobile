import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
import '../models/red_tide.dart';
import '../services/noaa_api.dart';
import '../services/fwc_api.dart';

final selectedStationProvider = StateProvider<Station?>((_) => null);

final selectedDateProvider = StateProvider<DateTime>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final tideDataProvider = FutureProvider<TideData?>((ref) async {
  final station = ref.watch(selectedStationProvider);
  if (station == null) return null;
  final date = ref.watch(selectedDateProvider);
  return fetchAllData(station, targetDate: date);
});

/// SST anomaly at/below this (°C vs. normal) reads as an upwelling signal —
/// shared by the Conditions-card banner and the upwelling notification.
const kUpwellingThresholdC = -1.5;

/// Daily MUR SST anomaly near the selected station (°C). Deliberately
/// independent of [tideDataProvider] so a slow or down ERDDAP server can
/// never delay the tide screen.
final sstAnomalyProvider = FutureProvider<double?>((ref) async {
  final station = ref.watch(selectedStationProvider);
  if (station == null) return null;
  return fetchSstAnomaly(station.lat, station.lon);
});

/// Karenia brevis (red tide) cell count at/above this reads as a real
/// advisory (FWC's own "low" threshold) rather than a trace detection.
const kRedTideThresholdCount = 10000.0;

/// Highest-count nearby FWC red-tide sample (Florida only; null everywhere
/// else, including no error). Independent of [tideDataProvider] so a slow
/// or down FWC server can never delay the tide screen.
final redTideProvider = FutureProvider<RedTideSample?>((ref) async {
  final station = ref.watch(selectedStationProvider);
  if (station == null) return null;
  return fetchNearbyRedTide(station.lat, station.lon);
});

final showWeekProvider = StateProvider<bool>((_) => false);

final weekDataProvider = FutureProvider<List<TidePrediction>>((ref) async {
  final station = ref.watch(selectedStationProvider);
  if (station == null) return [];
  // Rolling 7-day forecast starting today (not the calendar week, which would
  // show mostly past days late in the week and mis-map NWS day-name forecasts).
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 6));
  return fetchWeekHilo(station.id, today, end);
});
