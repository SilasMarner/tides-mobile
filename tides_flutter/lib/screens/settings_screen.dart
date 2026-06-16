import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/captain_email_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/tournament_mode_provider.dart';
import '../providers/units_provider.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _canExact = true;
  bool _notifEnabled = true;
  int? _pendingCount;
  bool _rescheduling = false;
  final _captainEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captainEmailCtrl.text = ref.read(captainEmailProvider);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captainEmailCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        NotificationService.checkCanExact(),
        NotificationService.checkNotificationsEnabled(),
        NotificationService.pendingCount(),
      ]);
      if (mounted) setState(() {
        _canExact = results[0] as bool;
        _notifEnabled = results[1] as bool;
        _pendingCount = results[2] as int;
      });
    } catch (_) {
      if (mounted) setState(() {
        _canExact = false;
        _notifEnabled = false;
        _pendingCount = 0;
      });
    }
  }

  Future<void> _rescheduleNow() async {
    setState(() { _rescheduling = true; _pendingCount = null; });
    try {
      await NotificationService.rescheduleAllStations();
      final count = await NotificationService.pendingCount();
      if (mounted) setState(() { _rescheduling = false; _pendingCount = count; });
    } catch (_) {
      if (mounted) setState(() { _rescheduling = false; _pendingCount = 0; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);
    final favorites = ref.watch(favoritesProvider);
    final metric = ref.watch(unitsProvider);
    final tournamentMode = ref.watch(tournamentModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: kNavyLight,
        foregroundColor: kCyan,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Units ────────────────────────────────────────────────────────
          _sectionLabel('UNITS'),
          const SizedBox(height: 8),
          Card(
            color: kCardBg,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ({'metric': false, 'label': 'Standard', 'sub': '°F · mph · ft'}),
                  ({'metric': true, 'label': 'Metric', 'sub': '°C · km/h · m'}),
                ].map((opt) {
                  final selected = metric == opt['metric'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(unitsProvider.notifier).setMetric(opt['metric'] as bool),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? kCyan : kNavy,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? kCyan : Colors.white24,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              opt['label'] as String,
                              style: TextStyle(
                                color: selected ? kNavy : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              opt['sub'] as String,
                              style: TextStyle(
                                color: selected
                                    ? kNavy.withValues(alpha: 0.7)
                                    : Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Catch Log ────────────────────────────────────────────────────
          _sectionLabel('CATCH LOG'),
          const SizedBox(height: 8),
          Card(
            color: kCardBg,
            child: SwitchListTile(
              value: tournamentMode,
              activeThumbColor: kCyan,
              title: const Text('Tournament Mode',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Show tournament tagging, requirements & info in Catch Log',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              secondary: Icon(
                Icons.emoji_events_outlined,
                color: tournamentMode ? kCyan : Colors.white38,
              ),
              onChanged: (v) =>
                  ref.read(tournamentModeProvider.notifier).setEnabled(v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: kCardBg,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _captainEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Captain's email (optional)",
                  labelStyle: TextStyle(color: Colors.white54),
                  helperText:
                      'Used as the default recipient when emailing catches',
                  helperStyle: TextStyle(color: Colors.white38, fontSize: 11),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    ref.read(captainEmailProvider.notifier).setEmail(v.trim()),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Master switch ───────────────────────────────────────────────
          Card(
            color: kCardBg,
            child: SwitchListTile(
              value: prefs.enabled,
              activeThumbColor: kCyan,
              title: const Text('Tide Notifications',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: const Text('Alerts for tides, solunar & fishing',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              secondary: Icon(
                prefs.enabled ? Icons.notifications_active : Icons.notifications_off,
                color: prefs.enabled ? kCyan : Colors.white38,
              ),
              onChanged: (v) async {
                await notifier.setEnabled(v);
              },
            ),
          ),

          if (prefs.enabled && !_notifEnabled) ...[
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF3A0000),
              child: ListTile(
                leading: const Icon(Icons.notifications_off, color: Colors.redAccent),
                title: const Text(
                  'Notifications are blocked',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Tap Allow, or go to Settings → Apps → OpenTides → Notifications.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final granted = await NotificationService.requestPermission();
                    if (granted) {
                      _refresh();
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Go to Settings → Apps → OpenTides → Notifications'),
                        duration: Duration(seconds: 4),
                      ));
                    }
                  },
                  child: const Text('Allow',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
          ],

          if (prefs.enabled && _notifEnabled && !_canExact) ...[
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF3A2800),
              child: ListTile(
                leading: const Icon(Icons.alarm_off, color: Colors.amber),
                title: const Text(
                  'Alerts may be delayed',
                  style: TextStyle(
                      color: Colors.amber, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Allow "Alarms & Reminders" so tide alerts fire on time.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: NotificationService.openExactAlarmSettings,
                  child: const Text('Fix',
                      style: TextStyle(color: Colors.amber)),
                ),
              ),
            ),
          ],

          if (prefs.enabled) ...[
            const SizedBox(height: 16),

            // ── Lead time ─────────────────────────────────────────────────
            _sectionLabel('NOTIFY ME HOW FAR IN ADVANCE'),
            const SizedBox(height: 8),
            Card(
              color: kCardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [15, 30, 45, 60].map((m) {
                    final selected = prefs.leadMinutes == m;
                    return GestureDetector(
                      onTap: () => notifier.setLeadMinutes(m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? kCyan : kNavy,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? kCyan : Colors.white24,
                          ),
                        ),
                        child: Text(
                          '${m}m',
                          style: TextStyle(
                            color: selected ? kNavy : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Event types ────────────────────────────────────────────────
            _sectionLabel('NOTIFY ME ABOUT'),
            const SizedBox(height: 8),
            Card(
              color: kCardBg,
              child: Column(
                children: [
                  _eventToggle(
                    icon: Icons.waves,
                    label: 'High & Low Tide',
                    subtitle: 'Alert before each tide change',
                    value: prefs.notifyTides,
                    onChanged: notifier.setNotifyTides,
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _eventToggle(
                    icon: Icons.brightness_3,
                    label: 'Solunar Major Windows',
                    subtitle: 'Peak feeding periods',
                    value: prefs.notifySolunarMajor,
                    onChanged: notifier.setNotifySolunarMajor,
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _eventToggle(
                    icon: Icons.set_meal,
                    label: 'Best Fishing Days',
                    subtitle: '4+ star rating — morning alert only',
                    value: prefs.notifyFishing,
                    onChanged: notifier.setNotifyFishing,
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _eventToggle(
                    icon: Icons.trending_down,
                    label: 'Pressure Drops',
                    subtitle: 'Falling barometer — front approaching',
                    value: prefs.notifyPressureDrop,
                    onChanged: notifier.setNotifyPressureDrop,
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _eventToggle(
                    icon: Icons.ac_unit,
                    label: 'Upwelling',
                    subtitle: 'Water much colder than normal nearby',
                    value: prefs.notifyUpwelling,
                    onChanged: notifier.setNotifyUpwelling,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Per-station toggles ─────────────────────────────────────────
            _sectionLabel('MY STATIONS'),
            const SizedBox(height: 8),
            if (favorites.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Save a station as a favorite to enable notifications for it.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              )
            else
              Card(
                color: kCardBg,
                child: Column(
                  children: favorites.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;
                    final on = prefs.stations.contains(s.id);
                    return Column(
                      children: [
                        SwitchListTile(
                          dense: true,
                          activeThumbColor: kCyan,
                          value: on,
                          title: Text(s.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          subtitle: Text('Station ${s.id}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          secondary: Icon(
                            on ? Icons.notifications : Icons.notifications_none,
                            color: on ? kCyan : Colors.white38,
                            size: 20,
                          ),
                          onChanged: (_) => notifier.toggleStation(s.id),
                        ),
                        if (i < favorites.length - 1)
                          const Divider(color: Colors.white10, height: 1),
                      ],
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 16),
            _sectionLabel('ALERT STATUS'),
            const SizedBox(height: 8),
            Card(
              color: kCardBg,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusRow(
                      'Notification permission',
                      _notifEnabled,
                      _notifEnabled ? 'Allowed' : 'Blocked',
                    ),
                    const SizedBox(height: 6),
                    _statusRow(
                      'Exact alarm timing',
                      _canExact,
                      _canExact ? 'Active' : 'Inactive — alerts may be delayed',
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(
                        _pendingCount == null
                            ? Icons.hourglass_empty
                            : _pendingCount! > 0
                                ? Icons.alarm_on
                                : Icons.alarm_off,
                        size: 14,
                        color: _pendingCount == null
                            ? Colors.white38
                            : _pendingCount! > 0
                                ? Colors.greenAccent
                                : Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _pendingCount == null
                            ? 'Checking…'
                            : '$_pendingCount tide alert${_pendingCount == 1 ? '' : 's'} scheduled',
                        style: TextStyle(
                          fontSize: 12,
                          color: _pendingCount == null
                              ? Colors.white38
                              : _pendingCount! > 0
                                  ? Colors.white70
                                  : Colors.amber,
                        ),
                      ),
                    ]),
                    const Divider(color: Colors.white10, height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kCyan,
                          side: const BorderSide(color: kCyan),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          try {
                            await NotificationService.scheduleTestIn2Min();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Scheduled — you should get an alert in ~2 min'),
                                duration: Duration(seconds: 4),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Could not schedule: $e'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 6),
                            ));
                          }
                        },
                        child: const Text('Test scheduled alert (2 min)',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.notification_add_outlined,
                            size: 14, color: kCyan),
                        label: const Text('Send instant test',
                            style: TextStyle(color: kCyan, fontSize: 11)),
                        onPressed: () async {
                          final ok =
                              await NotificationService.sendTestNotification();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Instant test sent — check your shade'
                                : 'Blocked — tap Allow above first'),
                            duration: const Duration(seconds: 3),
                          ));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _rescheduling ? null : _rescheduleNow,
                child: _rescheduling
                    ? const SizedBox(
                        height: 14, width: 14,
                        child: CircularProgressIndicator(
                            color: kCyan, strokeWidth: 2))
                    : const Text('Reschedule alerts now',
                        style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Alerts are rescheduled automatically each time you open the app.',
              style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusRow(String label, bool ok, String value) => Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 14,
              color: ok ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12),
                children: [
                  TextSpan(
                      text: '$label: ',
                      style: const TextStyle(color: Colors.white54)),
                  TextSpan(
                      text: value,
                      style: TextStyle(
                          color: ok ? Colors.white70 : Colors.redAccent)),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: kCyan, fontSize: 11, letterSpacing: 1.5),
      );

  Widget _eventToggle({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) =>
      SwitchListTile(
        dense: true,
        activeThumbColor: kCyan,
        secondary: Icon(icon, color: value ? kCyan : Colors.white38, size: 20),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        value: value,
        onChanged: onChanged,
      );
}
