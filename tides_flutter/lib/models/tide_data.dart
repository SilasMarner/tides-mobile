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
  });
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

class FishingInfo {
  final int stars;
  final String label;

  const FishingInfo({required this.stars, required this.label});
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
  final String ndbcStation;
  final double distance;      // miles from tide station

  const WaveData({
    required this.waveHeight,
    required this.domPeriod,
    this.waveDir,
    this.swellHeight,
    this.swellPeriod,
    this.swellDir,
    this.windWaveHeight,
    this.windWavePeriod,
    required this.ndbcStation,
    required this.distance,
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
  });
}
