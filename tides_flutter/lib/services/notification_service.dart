import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/station.dart';
import '../models/tide_data.dart';
import '../models/notification_prefs.dart';
import '../utils/unit_format.dart';
import 'noaa_api.dart' show fetchWeekHilo;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _canExact = false;

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

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Ensure the channel exists with high importance before any notification fires.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'tides_alerts',
        'Tide Alerts',
        description: 'Tide, solunar, and fishing notifications',
        importance: Importance.high,
      ),
    );

    // API 31+: exact alarms need SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM.
    _canExact = await androidImpl?.canScheduleExactNotifications() ?? false;

    _initialized = true;
  }

  /// Re-checks exact-alarm availability (call after returning from system settings).
  static Future<bool> checkCanExact() async {
    if (!_initialized) await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    _canExact = await androidImpl?.canScheduleExactNotifications() ?? false;
    return _canExact;
  }

  /// Whether POST_NOTIFICATIONS permission is granted (Android 13+).
  static Future<bool> checkNotificationsEnabled() async {
    if (!_initialized) await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await androidImpl?.areNotificationsEnabled() ?? true;
  }

  /// Cancel every pending scheduled notification. Call before rescheduleAllStations()
  /// so pendingNotificationRequests() is always fast.
  static Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }

  /// Number of pending (not yet fired) scheduled notifications.
  static Future<int> pendingCount() async {
    if (!_initialized) await init();
    return (await _plugin.pendingNotificationRequests()).length;
  }

  /// Schedule a test notification 2 minutes from now using the exact same
  /// code path as real tide alerts. If this fires, AlarmManager is working.
  static Future<void> scheduleTestIn2Min() async {
    await init();
    await _schedule(
      id: 0x7FFFFE00,
      title: '🌊 OpenTides — Scheduled test',
      body: 'If you see this, tide alert scheduling works correctly.',
      at: DateTime.now().add(const Duration(minutes: 2)),
      payload: 'test',
    );
  }

  /// Fire an immediate test notification. Returns false if the permission is denied.
  static Future<bool> sendTestNotification() async {
    await init();
    final enabled = await checkNotificationsEnabled();
    if (!enabled) return false;
    await _plugin.show(
      0x7FFFFF00, // reserved test ID
      '🌊 OpenTides — Notifications work!',
      'If you see this, alerts are set up correctly.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tides_alerts',
          'Tide Alerts',
          channelDescription: 'Tide, solunar, and fishing notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
    return true;
  }

  /// Opens the system Alarms & Reminders page for this app (API 31+).
  static Future<void> openExactAlarmSettings() async {
    if (!_initialized) await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestExactAlarmsPermission();
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

  /// Called at every app start. Re-schedules 7-day HiLo tide alerts for all
  /// notification-enabled stations so alarms survive reboots and app updates
  /// without the user having to open each station individually.
  static Future<void> rescheduleAllStations() async {
    try {
      await init();
      // Wipe ALL pending notifications first. Before build 61, cancelForStation
      // had no payloads to match so stale alarms accumulated across every launch.
      // Hundreds of stale entries exhaust AlarmManager slots and make
      // pendingNotificationRequests() hang. Start clean every time.
      await _plugin.cancelAll();
      final sp = await SharedPreferences.getInstance();

      final prefsStr = sp.getString('notification_prefs');
      if (prefsStr == null) return;
      final prefs = NotificationPrefs.fromJsonString(prefsStr);
      if (!prefs.enabled || prefs.stations.isEmpty || !prefs.notifyTides) return;

      final favsStr = sp.getString('favorites');
      if (favsStr == null) return;
      final favorites = (jsonDecode(favsStr) as List)
          .map((j) => Station.fromJson(j as Map<String, dynamic>))
          .toList();

      final metric = sp.getBool('use_metric') ?? false;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final end = today.add(const Duration(days: 6));

      for (final station in favorites) {
        if (!prefs.stations.contains(station.id)) continue;
        try {
          final weekHilo = await fetchWeekHilo(station.id, today, end);
          if (weekHilo.isEmpty) continue;
          await cancelForStation(station.id);
          final lead = Duration(minutes: prefs.leadMinutes);
          for (final p in weekHilo) {
            if (p.type == null) continue;
            final notifyAt = p.time.subtract(lead);
            if (!notifyAt.isAfter(now)) continue;
            final isHigh = p.type == 'H';
            await _schedule(
              id: _id(station.id, 'tide', p.time),
              title: isHigh
                  ? '🌊 High Tide in ${prefs.leadMinutes} min'
                  : '🏖️ Low Tide in ${prefs.leadMinutes} min',
              body:
                  '${station.name} · ${_fmt(p.time)} · ${fmtTideHeight(p.height, metric)}',
              at: notifyAt,
              payload: station.id,
            );
          }
        } catch (_) {
          // Skip on network error — retries on next launch.
        }
      }
    } catch (_) {
      // Never crash main() on notification failure.
    }
  }

  static Future<void> scheduleForStation(
    String stationId,
    String stationName,
    TideData data,
    NotificationPrefs prefs, {
    bool metric = false,
    // When provided, tide notifications cover the full list (7-day window)
    // rather than just today's remaining events.
    List<TidePrediction>? weekHilo,
  }) async {
    await init();
    await cancelForStation(stationId);

    final now = DateTime.now();
    final lead = Duration(minutes: prefs.leadMinutes);

    // Hi/Lo tide events — prefer week range so alerts survive past today's last tide.
    if (prefs.notifyTides) {
      for (final p in (weekHilo ?? data.hilo)) {
        if (p.type == null) continue; // skip hourly points if mixed in
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
            payload: stationId,
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
            payload: stationId,
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
          payload: stationId,
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

  /// Upwelling heads-up: SST anomaly well below normal near the station.
  /// The anomaly arrives via its own provider (not TideData), so this is a
  /// standalone entry point rather than part of [scheduleForStation]. Fired
  /// immediately when the anomaly loads, deduped to once per station per day.
  static Future<void> maybeUpwellingAlert(
    String stationId,
    String stationName,
    double anomalyC, {
    bool metric = false,
  }) async {
    await init();
    final sp = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final key =
        'upwellAlert_${stationId}_${today.year}${today.month}${today.day}';
    if (sp.getBool(key) == true) return;
    await sp.setBool(key, true);
    await _plugin.show(
      _id(stationId, 'upwelling', today),
      '🌊 Upwelling Detected — $stationName',
      'Water ${fmtTempDelta(anomalyC.abs(), metric)} colder than normal — '
          'cooler, often nutrient-rich water moving in near this station.',
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
    required String payload,
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
      androidScheduleMode: _canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
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
