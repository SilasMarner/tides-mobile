import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: TidesApp()));
}

class TidesApp extends StatelessWidget {
  const TidesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tides',
        theme: buildTheme(),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      );
}
