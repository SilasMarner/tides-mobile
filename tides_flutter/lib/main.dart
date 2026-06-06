import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
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
