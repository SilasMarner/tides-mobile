import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kNightKey = 'night_mode';

/// Global night-mode preference.
///
/// `false` = standard navy theme (the default).
/// `true`  = high-contrast night theme: pure-black background so text and the
///           cyan accents read with more contrast in the dark (e.g. on the
///           water at night).
final nightModeProvider = StateNotifierProvider<NightModeNotifier, bool>(
  (ref) => NightModeNotifier(),
);

class NightModeNotifier extends StateNotifier<bool> {
  NightModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kNightKey) ?? false;
  }

  Future<void> toggle() => set(!state);

  Future<void> set(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNightKey, v);
  }
}
