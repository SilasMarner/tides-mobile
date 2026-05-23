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

final weekDataProvider = FutureProvider<List<TidePrediction>>((ref) async {
  final station = ref.watch(selectedStationProvider);
  if (station == null) return [];
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final sunday = monday.add(const Duration(days: 6));
  return fetchWeekHilo(station.id, monday, sunday);
});
