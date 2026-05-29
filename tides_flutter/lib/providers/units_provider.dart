import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kUnitsKey = 'use_metric';

/// Global measurement-units preference.
///
/// `false` = Standard (°F, mph, ft) — the default.
/// `true`  = Metric (°C, km/h, m).
final unitsProvider = StateNotifierProvider<UnitsNotifier, bool>(
  (ref) => UnitsNotifier(),
);

class UnitsNotifier extends StateNotifier<bool> {
  UnitsNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kUnitsKey) ?? false;
  }

  Future<void> setMetric(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUnitsKey, v);
  }
}
