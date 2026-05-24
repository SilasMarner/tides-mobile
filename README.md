# Tides — Live NOAA Tide App for Android

A Flutter app for Android that shows real-time NOAA tide data, weather conditions, solunar tables, and fishing ratings. Built for fishermen and boaters who need quick, reliable tidal information on the water.

## Download

**[Latest release on GitHub Releases](https://github.com/SilasMarner/tides-mobile/releases/latest)** — download the `.apk` and tap to install.

To sideload: enable *Install unknown apps* for your file manager in Android Settings → Apps, download the APK, and tap to install.

---

## Features

- **Live tide charts** — smooth cosine-interpolated curves with high/low dot markers and a current-time dashed line
- **All ~3,450 NOAA stations** — search by city, station name, or state
- **Subordinate stations** — cosine interpolation fills hourly data for stations that only publish hi/lo predictions
- **Real-time conditions** — air temp, water temp, barometric pressure (with trend ↑↓), water level, **salinity**
- **Salinity** — shown when the station has a sensor (PSU / ppt)
- **NWS weather** — current conditions + 7-day forecast per station; supplements missing NOAA sensor data
- **Week view** — 7 days of hi/lo tides with NWS temperature and short forecast per day; tap any day to expand the full detailed forecast
- **Solunar tables** — major/minor feeding periods calculated from moon position
- **Sun & moon** — sunrise, sunset, golden hour, moon phase and illumination percentage
- **Fishing rating** — 1–5 star rating based on tidal movement, solunar timing, and wind
- **Favorites** — save stations with one tap; shown on home screen
- **Use My Location** — GPS-based nearest stations

---

## Screenshots

> Coming soon — see the [releases page](https://github.com/SilasMarner/tides-mobile/releases) for screenshots.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter 3.44+ / Material 3 |
| State | Riverpod (FutureProvider, StateProvider) |
| Charts | fl_chart |
| HTTP | Dio |
| Location | Geolocator |
| Storage | shared_preferences |
| Tide data | NOAA CO-OPS API |
| Weather | NWS weather.gov API |

---

## Building from Source

### Prerequisites
- Flutter SDK 3.44+
- Android SDK with API 35+
- Java 17

```bash
cd tides_flutter
flutter pub get
flutter build apk --release
```

### Debug (emulator x86_64)
```bash
flutter build apk --debug --target-platform android-x64
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### Signed release build
Create `tides_flutter/android/key.properties` — **never commit this file**:

```properties
storeFile=../../tides.keystore
storePassword=YOUR_STORE_PASSWORD
keyAlias=tides
keyPassword=YOUR_KEY_PASSWORD
```

Then build the App Bundle for Play Store submission:
```bash
flutter build appbundle --release
# Output: tides_flutter/build/app/outputs/bundle/release/app-release.aab
```

---

## App ID

`com.mattbettinger.tides`

---

## Data Sources

Both APIs are free and require no API key:

- **NOAA CO-OPS API** — tide predictions, observations, water level, salinity  
  https://api.tidesandcurrents.noaa.gov/
- **NWS / weather.gov** — 7-day forecasts and hourly conditions  
  https://api.weather.gov/

---

## Project Structure

```
tides-mobile/
├── tides_flutter/       Flutter app (primary)
│   ├── lib/
│   │   ├── models/      Data models (TideData, Conditions, etc.)
│   │   ├── providers/   Riverpod state providers
│   │   ├── screens/     HomeScreen, DetailScreen, AboutScreen
│   │   ├── services/    noaa_api.dart, location_service.dart
│   │   └── widgets/     TideChart, ConditionsCard, StationTile
│   └── android/         Android build config
└── legacy/              Original Python/Kivy v1.2 (archived)
```

---

## Developer

Matt Bettinger — tides-mobile.human695@passmail.com

---

## License

MIT — free to use, modify, and distribute.
