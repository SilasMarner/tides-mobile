import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/noaa_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15 (SDK 35) draws apps edge-to-edge by default. Opt in explicitly
  // and make both system bars transparent so our content draws behind them;
  // Scaffold/AppBar/SafeArea handle the actual insets. Light icons suit the
  // app's dark navy/black chrome in both day and night themes.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
  await hydrateCacheFromDisk();
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
