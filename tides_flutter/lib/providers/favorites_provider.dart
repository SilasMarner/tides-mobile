import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/station.dart';

const _key = 'favorites';

class FavoritesNotifier extends StateNotifier<List<Station>> {
  FavoritesNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      state = list.map((j) => Station.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((s) => s.toJson()).toList()));
  }

  Future<bool> add(Station station) async {
    if (state.any((s) => s.id == station.id)) return false;
    state = [...state, station];
    await _save();
    return true;
  }

  Future<bool> remove(String stationId) async {
    final next = state.where((s) => s.id != stationId).toList();
    if (next.length == state.length) return false;
    state = next;
    await _save();
    return true;
  }

  bool contains(String stationId) => state.any((s) => s.id == stationId);
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Station>>(
  (_) => FavoritesNotifier(),
);
