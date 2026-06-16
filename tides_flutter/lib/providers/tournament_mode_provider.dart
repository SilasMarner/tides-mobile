import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTournamentModeKey = 'tournament_mode_enabled';

/// Whether tournament tagging/checklists/info show up in the Catch Log.
/// Defaults to on; users who just want a plain catch log can turn it off
/// in Settings.
final tournamentModeProvider =
    StateNotifierProvider<TournamentModeNotifier, bool>(
  (ref) => TournamentModeNotifier(),
);

class TournamentModeNotifier extends StateNotifier<bool> {
  TournamentModeNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kTournamentModeKey) ?? true;
  }

  Future<void> setEnabled(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTournamentModeKey, v);
  }
}
