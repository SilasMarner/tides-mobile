import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notification_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/units_provider.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);
    final favorites = ref.watch(favoritesProvider);
    final metric = ref.watch(unitsProvider);

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
                if (v) await NotificationService.requestPermission();
                await notifier.setEnabled(v);
              },
            ),
          ),

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

            const SizedBox(height: 24),
            const Text(
              'Notifications are scheduled each time you open a station. '
              'Keep the app installed to receive alerts.',
              style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

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
