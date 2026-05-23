import 'package:flutter/material.dart';

const Color kNavy = Color(0xFF0A1628);
const Color kNavyLight = Color(0xFF0D2137);
const Color kCyan = Color(0xFF00BCD4);
const Color kCyanLight = Color(0xFF4DD0E1);
const Color kCardBg = Color(0xFF0F1F35);
const Color kHighTide = Color(0xFF4DD0E1);
const Color kLowTide = Color(0xFF1565C0);

ThemeData buildTheme() => ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: kCyan,
        secondary: kCyanLight,
        surface: kNavyLight,
        onPrimary: kNavy,
        onSecondary: kNavy,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: kNavy,
      cardColor: kCardBg,
      useMaterial3: true,
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: kCyan, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        labelSmall: TextStyle(color: Colors.white54),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kNavyLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCyan, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kCyan.withOpacity(0.4), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kCyan, width: 2),
        ),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kCyan,
          foregroundColor: kNavy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
