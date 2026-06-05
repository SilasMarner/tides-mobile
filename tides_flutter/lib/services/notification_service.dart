import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/tide_data.dart';
import '../models/notification_prefs.dart';
import '../utils/unit_format.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  static Future<void> scheduleForStation(
    String stationId,
    String stationName,
    TideData data,
    NotificationPrefs prefs, {
    bool metric = false,
  }) async {
    await init();
    await cancelForStation(stationId);

    final now = DateTime.now();
    final lead = Duration(minutes: prefs.leadMinutes);

    // Hi/Lo tide events
    if (prefs.notifyTides) {
      for (final p in data.hilo) {
        final notifyAt = p.time.subtract(lead);
        if (notifyAt.isAfter(now)) {
          final isHigh = p.type == 'H';
          await _schedule(
            id: _id(stationId, 'tide', p.time),
            title: isHigh
                ? '🌊 High Tide in ${prefs.leadMinutes} min'
                : '🏖️ Low Tide in ${prefs.leadMinutes} min',
            body:
                '$stationName · ${_fmt(p.time)} · ${fmtTideHeight(p.height, metric)}',
            at: notifyAt,
          );
        }
      }
    }

    // Solunar major feeding windows
    if (prefs.notifySolunarMajor) {
      for (final h in [data.solunar.major1, data.solunar.major2]) {
        final eventTime = _hToDateTime(data.targetDate, h);
        final notifyAt = eventTime.subtract(lead);
        if (notifyAt.isAfter(now)) {
          await _schedule(
            id: _id(stationId, 'major', eventTime),
            title: '🎣 Solunar Major in ${prefs.leadMinutes} min',
            body: '$stationName · ${_fmt(eventTime)} · Peak feeding window',
            at: notifyAt,
          );
        }
      }
    }

    // Best fishing — single morning alert if 4+ stars today
    if (prefs.notifyFishing && data.isToday && data.fishing.stars >= 4) {
      final morningAlert = DateTime(
        data.targetDate.year,
        data.targetDate.month,
        data.targetDate.day,
        6,
        0,
      );
      if (morningAlert.isAfter(now)) {
        final stars = '★' * data.fishing.stars + '☆' * (5 - data.fishing.stars);
        await _schedule(
          id: _id(stationId, 'fishing', morningAlert),
          title: '🐟 Great Fishing Day — $stationName',
          body: '$stars  ${data.fishing.label}',
          at: morningAlert,
        );
      }
    }

    // Cold-front heads-up: falling barometer = fish often feed ahead of a
    // front. Fired immediately on refresh (no background worker), deduped to
    // once per station per day so repeated refreshes don't spam.
    if (prefs.notifyPressureDrop &&
        data.isToday &&
        data.conditions.pressureTrend < 0) {
      await _maybePressureAlert(stationId, stationName);
    }
  }

  static Future<void> _maybePressureAlert(
      String stationId, String stationName) async {
    final sp = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final key =
        'pressAlert_${stationId}_${today.year}${today.month}${today.day}';
    if (sp.getBool(key) == true) return;
    await sp.setBool(key, true);
    await _plugin.show(
      _id(stationId, 'pressure', today),
      '📉 Pressure Falling — $stationName',
      'Barometer dropping, front approaching — fish may feed ahead of it.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tides_alerts',
          'Tide Alerts',
          channelDescription: 'Tide, solunar, and fishing notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: stationId,
    );
  }

  static Future<void> cancelForStation(String stationId) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      // Notification IDs for this station all hash to the same base range
      // We tag them via the payload which contains the stationId
      if ((n.payload ?? '').startsWith(stationId)) {
        await _plugin.cancel(n.id);
      }
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  static Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    final tzAt = tz.TZDateTime.from(at, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tides_alerts',
          'Tide Alerts',
          channelDescription: 'Tide, solunar, and fishing notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static int _id(String stationId, String type, DateTime time) =>
      '$stationId:$type:${time.millisecondsSinceEpoch}'.hashCode & 0x7FFFFFFF;

  static DateTime _hToDateTime(DateTime date, double h) {
    final hour = h.floor();
    final min = ((h - hour) * 60).round();
    return DateTime(date.year, date.month, date.day, hour, min);
  }

  static String _fmt(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}
