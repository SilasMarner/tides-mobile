import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/catch_entry.dart';

const _key = 'catch_log';

class CatchLogNotifier extends StateNotifier<List<CatchEntry>> {
  CatchLogNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      final entries =
          list.map((j) => CatchEntry.fromJson(j as Map<String, dynamic>)).toList();
      // Newest first.
      entries.sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
      state = entries;
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  Future<void> add(CatchEntry entry) async {
    state = [entry, ...state]
      ..sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
    await _save();
  }

  Future<void> update(CatchEntry entry) async {
    state = state.map((e) => e.id == entry.id ? entry : e).toList()
      ..sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
    await _save();
  }

  Future<void> remove(String id) async {
    final removed = state.where((e) => e.id == id);
    for (final e in removed) {
      final path = e.photoPath;
      if (path != null) {
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

final catchLogProvider =
    StateNotifierProvider<CatchLogNotifier, List<CatchEntry>>(
  (_) => CatchLogNotifier(),
);
