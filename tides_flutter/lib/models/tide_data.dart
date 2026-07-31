import 'package:flutter/foundation.dart';

class TidePrediction {
  final DateTime time;
  final double height;
  final String? type; // 'H' or 'L' for hilo, null for hourly

  const TidePrediction({required this.time, required this.height, this.type});
}

class Conditions {
  final double? airTemp;
  final double? waterTemp;
  final double? windSpeed;
  final double? windDir;
  final double? windGust;
  final double? pressure;
  final double? waterLevel;
  final double? salinity; // PSU (ppt) — null when station has no sensor
  final String? windDirStr;
  final String? beaufortStr;
  final int pressureTrend; // +1 rising, -1 falling, 0 steady
  // Observed water level minus the day's predicted tide height ("wind tide").
  // Positive = water stacked above prediction, negative = drained below. Null
  // when there's no live observation (future days / stations without a sensor).
  final double? windTide;

  const Conditions({
    this.airTemp,
    this.waterTemp,
    this.windSpeed,
    this.windDir,
    this.windGust,
    this.pressure,
    this.waterLevel,
    this.salinity,
    this.windDirStr,
    this.beaufortStr,
    this.pressureTrend = 0,
    this.windTide,
  });

  Conditions copyWith({
    double? airTemp,
    double? waterTemp,
    double? windSpeed,
    double? windDir,
    double? windGust,
    double? pressure,
    double? waterLevel,
    double? salinity,
    String? windDirStr,
    String? beaufortStr,
    int? pressureTrend,
    double? windTide,
  }) =>
      Conditions(
        airTemp: airTemp ?? this.airTemp,
        waterTemp: waterTemp ?? this.waterTemp,
        windSpeed: windSpeed ?? this.windSpeed,
        windDir: windDir ?? this.windDir,
        windGust: windGust ?? this.windGust,
        pressure: pressure ?? this.pressure,
        waterLevel: waterLevel ?? this.waterLevel,
        salinity: salinity ?? this.salinity,
        windDirStr: windDirStr ?? this.windDirStr,
        beaufortStr: beaufortStr ?? this.beaufortStr,
        pressureTrend: pressureTrend ?? this.pressureTrend,
        windTide: windTide ?? this.windTide,
      );
}

class NwsPeriod {
  final String name;
  final String shortForecast;
  final String detail;
  final int temp;

  const NwsPeriod({
    required this.name,
    required this.shortForecast,
    required this.detail,
    required this.temp,
  });
}

class NwsForecast {
  final String condition;
  final int temp;
  final int rainPct;
  final String windSpeed;
  final String windDir;
  final List<NwsPeriod> periods;

  const NwsForecast({
    required this.condition,
    required this.temp,
    required this.rainPct,
    required this.windSpeed,
    required this.windDir,
    required this.periods,
  });
}

class SunInfo {
  final String sunrise;
  final String sunset;
  final String noon;
  final String golden;

  const SunInfo({
    required this.sunrise,
    required this.sunset,
    required this.noon,
    required this.golden,
  });
}

class MoonInfo {
  final String phase;
  final int pct;

  const MoonInfo({required this.phase, required this.pct});
}

class SolunarInfo {
  final double major1;
  final double major2;
  final double minor1;
  final double minor2;

  const SolunarInfo({
    required this.major1,
    required this.major2,
    required this.minor1,
    required this.minor2,
  });
}

// A scored "go fishing" window for today, derived from tide movement +
// solunar + dawn/dusk. Hours are decimal local time (e.g. 14.0 = 2 PM).
class BiteWindow {
  final double startH;
  final double endH;
  final String reason; // short tag, e.g. "Incoming + Major"

  const BiteWindow({
    required this.startH,
    required this.endH,
    required this.reason,
  });
}

class FishingInfo {
  final int stars;
  final String label;
  // Today only: the best 2–3 bite windows and a one-line movement summary
  // (e.g. "Incoming — strongest 2–4 PM"). Empty/null for future days.
  final List<BiteWindow> windows;
  final String? movement;

  const FishingInfo({
    required this.stars,
    required this.label,
    this.windows = const [],
    this.movement,
  });
}

class WaveData {
  final double waveHeight;    // ft — significant wave height
  final double domPeriod;     // seconds — dominant period
  final String? waveDir;      // compass string, e.g. "SSW"
  final double? swellHeight;  // ft
  final double? swellPeriod;  // seconds
  final String? swellDir;
  final double? windWaveHeight; // ft
  final double? windWavePeriod; // seconds
  final String source;        // data attribution label

  const WaveData({
    required this.waveHeight,
    required this.domPeriod,
    this.waveDir,
    this.swellHeight,
    this.swellPeriod,
    this.swellDir,
    this.windWaveHeight,
    this.windWavePeriod,
    required this.source,
  });
}

@immutable
class TideData {
  final String stationId;
  final double lat;
  final double lon;
  final DateTime targetDate;
  final bool isToday;
  final Map<int, double> hourly; // hour 0-23 → height ft
  final List<TidePrediction> hilo;
  final Conditions conditions;
  final NwsForecast? nws;
  final SunInfo sun;
  final MoonInfo moon;
  final SolunarInfo solunar;
  final FishingInfo fishing;
  final WaveData? waves;

  /// True when this entry carries only tide predictions (curve + hi/lo +
  /// locally-computed sun/moon/solunar/fishing) with no live conditions —
  /// e.g. warmed by the background refresh task. The foreground always prefers
  /// a fresh live fetch over a partial entry; a partial is only served when the
  /// NOAA datagetter is unreachable. See [fetchAllData].
  final bool isPartial;

  /// When this entry was actually fetched/computed — not necessarily "now",
  /// since a NOAA outage or a cold background-warm can mean the caller is
  /// being served something fetched minutes or days ago. Lets the UI show a
  /// "showing saved data" indicator instead of silently presenting stale data
  /// as if it were live. See [DetailScreen]'s offline/cached banner.
  final DateTime fetchedAt;

  const TideData({
    required this.stationId,
    required this.lat,
    required this.lon,
    required this.targetDate,
    required this.isToday,
    required this.hourly,
    required this.hilo,
    required this.conditions,
    this.nws,
    required this.sun,
    required this.moon,
    required this.solunar,
    required this.fishing,
    this.waves,
    this.isPartial = false,
    required this.fetchedAt,
  });
}
