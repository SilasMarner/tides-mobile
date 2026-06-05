import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_prefs.dart';

const _kPrefsKey = 'notification_prefs';

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
  (ref) => NotificationPrefsNotifier(),
);

class NotificationPrefsNotifier extends StateNotifier<NotificationPrefs> {
  NotificationPrefsNotifier() : super(const NotificationPrefs()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kPrefsKey);
    if (s != null) {
      try {
        state = NotificationPrefs.fromJsonString(s);
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, state.toJsonString());
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await _save();
  }

  Future<void> setLeadMinutes(int m) async {
    state = state.copyWith(leadMinutes: m);
    await _save();
  }

  Future<void> setNotifyTides(bool v) async {
    state = state.copyWith(notifyTides: v);
    await _save();
  }

  Future<void> setNotifySolunarMajor(bool v) async {
    state = state.copyWith(notifySolunarMajor: v);
    await _save();
  }

  Future<void> setNotifyFishing(bool v) async {
    state = state.copyWith(notifyFishing: v);
    await _save();
  }

  Future<void> setNotifyPressureDrop(bool v) async {
    state = state.copyWith(notifyPressureDrop: v);
    await _save();
  }

  Future<void> toggleStation(String stationId) async {
    final current = Set<String>.from(state.stations);
    if (current.contains(stationId)) {
      current.remove(stationId);
    } else {
      current.add(stationId);
    }
    state = state.copyWith(stations: current);
    await _save();
  }

  bool stationEnabled(String stationId) => state.stations.contains(stationId);
}
