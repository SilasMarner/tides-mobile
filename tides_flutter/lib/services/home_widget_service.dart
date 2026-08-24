import 'package:flutter/services.dart' show MethodChannel, PlatformException;

/// Bridges the home-screen Tide widget's tap-to-open to Dart. Mirrors
/// [NotificationService]'s push (already running) / pull (cold start)
/// split — see MainActivity.kt's captureWidgetIntent for the native side.
class HomeWidgetService {
  static const _channel = MethodChannel('com.mattbettinger.tides/widget');
  static bool _initialized = false;

  /// Fires when a widget is tapped while the app is already running.
  static void Function(Map<String, dynamic> station)? onStationTapped;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openStation') {
        onStationTapped?.call(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  /// The station payload from a cold-start widget tap, if any. Call once,
  /// after the first frame.
  static Future<Map<String, dynamic>?> consumePendingStation() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('consumePendingStation');
      return result;
    } on PlatformException {
      return null;
    }
  }
}
