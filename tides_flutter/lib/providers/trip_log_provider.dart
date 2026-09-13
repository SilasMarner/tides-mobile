import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';

const _key = 'trip_log';

class TripLogNotifier extends StateNotifier<List<Trip>> {
  TripLogNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      final trips =
          list.map((j) => Trip.fromJson(j as Map<String, dynamic>)).toList();
      // Soonest first — trips are forward-looking, unlike the catch log.
      trips.sort((a, b) => a.plannedDate.compareTo(b.plannedDate));
      state = trips;
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  Future<void> add(Trip trip) async {
    state = [...state, trip]..sort((a, b) => a.plannedDate.compareTo(b.plannedDate));
    await _save();
  }

  Future<void> update(Trip trip) async {
    state = state.map((e) => e.id == trip.id ? trip : e).toList()
      ..sort((a, b) => a.plannedDate.compareTo(b.plannedDate));
    await _save();
  }

  Future<void> remove(String id) async {
    final removed = state.where((e) => e.id == id);
    for (final e in removed) {
      for (final path in e.photoPaths) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    state = state.where((e) => e.id != id).toList();
    await _save();
  }
}

final tripLogProvider = StateNotifierProvider<TripLogNotifier, List<Trip>>(
  (_) => TripLogNotifier(),
);
