import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLastTournamentKey = 'last_tournament_id';

/// The most recently selected tournament — used as the default selection on
/// the next new catch entry, since anglers usually log several catches in a
/// row for the same tournament.
final lastTournamentProvider =
    StateNotifierProvider<LastTournamentNotifier, String?>(
  (ref) => LastTournamentNotifier(),
);

class LastTournamentNotifier extends StateNotifier<String?> {
  LastTournamentNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kLastTournamentKey);
  }

  Future<void> setId(String? id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kLastTournamentKey);
    } else {
      await prefs.setString(_kLastTournamentKey, id);
    }
  }
}
