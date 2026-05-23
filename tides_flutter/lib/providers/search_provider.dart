import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../services/noaa_api.dart';

final searchQueryProvider = StateProvider<String>((_) => '');

final searchResultsProvider = FutureProvider<List<Station>>((ref) async {
  final q = ref.watch(searchQueryProvider);
  if (q.length < 2) return [];
  return searchStations(q);
});
