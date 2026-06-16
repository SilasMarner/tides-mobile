import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCaptainEmailKey = 'catch_captain_email';

/// Default recipient when emailing selected catches — e.g. a team captain
/// who enters them into a tournament's website.
final captainEmailProvider =
    StateNotifierProvider<CaptainEmailNotifier, String>(
  (ref) => CaptainEmailNotifier(),
);

class CaptainEmailNotifier extends StateNotifier<String> {
  CaptainEmailNotifier() : super('') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kCaptainEmailKey) ?? '';
  }

  Future<void> setEmail(String v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCaptainEmailKey, v);
  }
}
