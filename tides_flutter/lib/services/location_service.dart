import 'package:geolocator/geolocator.dart';
import '../services/noaa_api.dart' show apiGet;

Future<(double, double, String)?> getLocation() async {
  try {
    final perm = await Geolocator.checkPermission();
    final granted = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
    final effective = granted
        ? perm
        : await Geolocator.requestPermission();
    if (effective == LocationPermission.always ||
        effective == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10));
      return (pos.latitude, pos.longitude, 'your location');
    }
  } catch (_) {}

  // IP geolocation fallback
  for (final url in ['https://ipapi.co/json/', 'https://ip-api.com/json/']) {
    try {
      final data = await apiGet(url);
      if (data == null) continue;
      final lat = double.tryParse(
          (data['latitude'] ?? data['lat'] ?? '').toString());
      final lon = double.tryParse(
          (data['longitude'] ?? data['lon'] ?? '').toString());
      final city = data['city'] as String? ?? 'your location';
      if (lat != null && lon != null) return (lat, lon, city);
    } catch (_) {}
  }
  return null;
}
