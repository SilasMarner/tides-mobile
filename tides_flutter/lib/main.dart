import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/noaa_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  // Cancel ALL pending alarms before runApp so pendingNotificationRequests()
  // is always fast when Settings opens — stale entries from before build 61
  // accumulated into hundreds and caused the count to hang indefinitely.
  await NotificationService.cancelAll();
  await hydrateCacheFromDisk();
  // Reschedule fresh 7-day tide alarms for all enabled stations in the background.
  NotificationService.rescheduleAllStations().ignore();
  runApp(const ProviderScope(child: TidesApp()));
}

class TidesApp extends ConsumerWidget {
  const TidesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    return MaterialApp(
      title: 'OpenTides',
      theme: buildTheme(night: night),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
