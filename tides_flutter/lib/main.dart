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
  // Rehydrate the on-disk tide cache so reopening after Android evicted the
  // process serves previously-viewed days instantly, without refetching.
  await hydrateCacheFromDisk();
  // Re-schedule tide alerts for all enabled stations on every launch so alarms
  // survive reboots and app updates without requiring the user to open each station.
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
