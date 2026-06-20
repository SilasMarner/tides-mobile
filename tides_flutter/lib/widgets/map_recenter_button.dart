import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';

/// A small "recenter" crosshair button for the map screens. It fades in only
/// once the user has panned the station marker away from the centre of the
/// viewport, and snaps the camera back to the station when tapped. The station
/// pin itself always stays put (anchored to its coordinate) — this just gives a
/// one-tap way back after exploring. Drop it into a [Stack] above the map.
class MapRecenterButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onPressed;

  /// Bottom inset so the button clears each screen's own bottom chrome
  /// (legend / timeline / status card). Defaults to a value that clears a
  /// typical legend strip.
  final double bottom;

  const MapRecenterButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.bottom = 96,
  });

  /// True when the station has drifted out of the central ~30% of the viewport,
  /// i.e. far enough that a recenter affordance is worth showing. Zoom-
  /// independent: measured as a fraction of the visible span, so it behaves the
  /// same whether you're zoomed in or out.
  static bool offCenter(MapCamera camera, LatLng station) {
    final b = camera.visibleBounds;
    final latSpan = (b.north - b.south).abs();
    final lonSpan = (b.east - b.west).abs();
    if (latSpan == 0 || lonSpan == 0) return false;
    final dLat = (camera.center.latitude - station.latitude).abs();
    final dLon = (camera.center.longitude - station.longitude).abs();
    return dLat > latSpan * 0.15 || dLon > lonSpan * 0.15;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.only(right: 12, bottom: bottom),
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedScale(
                scale: visible ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Material(
                  color: kNavyLight,
                  shape: const CircleBorder(
                      side: BorderSide(color: Colors.white24)),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: const Padding(
                      padding: EdgeInsets.all(11),
                      child: Icon(Icons.my_location, color: kCyan, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
