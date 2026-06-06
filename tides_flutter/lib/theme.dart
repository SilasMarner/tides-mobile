import 'package:flutter/material.dart';

const Color kNavy = Color(0xFF0A1628);
const Color kNavyLight = Color(0xFF0D2137);
const Color kCyan = Color(0xFF00BCD4);
const Color kCyanLight = Color(0xFF4DD0E1);
const Color kCardBg = Color(0xFF0F1F35);
const Color kHighTide = Color(0xFF4DD0E1);
const Color kLowTide = Color(0xFF1565C0);

// High-contrast night palette. A pure-black background pushes the muted greys
// and cyan accents to higher contrast for easier reading in the dark.
const Color kNightBg = Color(0xFF000000);
const Color kNightSurface = Color(0xFF0A0E14);
const Color kNightCyan = Color(0xFF2BE7FF); // brighter cyan that pops on black

/// App bar background for the current mode (app bars are styled explicitly
/// across screens, so they read this rather than relying on the theme).
Color appBarColor(bool night) => night ? kNightBg : kNavyLight;

/// Bright accent (titles, icons) — brighter in night mode for more contrast.
Color accentColor(bool night) => night ? kNightCyan : kCyan;

ThemeData buildTheme({bool night = false}) => ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: night ? kNightCyan : kCyan,
        secondary: kCyanLight,
        surface: night ? kNightSurface : kNavyLight,
        onPrimary: kNavy,
        onSecondary: kNavy,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: night ? kNightBg : kNavy,
      cardColor: night ? kNightSurface : kCardBg,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: night ? kNightBg : kNavyLight,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
            color: night ? kNightCyan : kCyan, fontWeight: FontWeight.bold),
        titleMedium: const TextStyle(color: Colors.white),
        // Night mode brightens body/label text for readability on pure black.
        bodyMedium: TextStyle(color: night ? Colors.white : Colors.white70),
        labelSmall: TextStyle(color: night ? Colors.white70 : Colors.white54),
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
          borderSide: BorderSide(color: kCyan.withValues(alpha: 0.4), width: 1),
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
