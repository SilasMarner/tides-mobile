import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../models/tide_data.dart';
import '../services/noaa_api.dart';

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
