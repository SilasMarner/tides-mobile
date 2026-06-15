import 'package:flutter/material.dart';
import '../theme.dart';

/// A quick, scrollable user guide: what the app shows, where the data comes
/// from, how the fishing score is calculated, and how the alerts work.
class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('User Guide'),
          backgroundColor: kNavyLight,
          foregroundColor: kCyan,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text('How OpenTides works',
                style: TextStyle(
                    color: kCyan, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'A quick guide to reading the app, where the numbers come from, '
              'and how the fishing score and alerts are calculated. Everything '
              'is computed on your phone from free public data — no account, no '
              'tracking, no ads.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            ..._sections.map(_buildSection),
          ],
        ),
      );

  Widget _buildSection(_Section s) => Card(
        color: kCardBg,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(s.icon, color: kCyan, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.title,
                        style: const TextStyle(
                            color: kCyan,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...s.body.map((b) => b.startsWith('• ')
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(color: kCyan, fontSize: 13)),
                          Expanded(
                            child: Text(b.substring(2),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.45)),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(b,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.45)),
                    )),
            ],
          ),
        ),
      );

  static const _sections = <_Section>[
    _Section(
      Icons.public,
      'Where the data comes from',
      [
        'Every figure is pulled live from official, free sources and combined on your device:',
        '• Tides — NOAA CO-OPS (tidesandcurrents.noaa.gov): official predictions and real-time water level, water temp, air temp, wind, barometric pressure, and salinity from ~3,450 stations.',
        '• Weather & forecast — the U.S. National Weather Service (weather.gov) for the per-station 7-day forecast.',
        '• Waves & marine — Open-Meteo Marine for wave height, swell, and period at the station’s location.',
        '• Ocean maps — NOAA CoastWatch satellite products: JPL MUR sea-surface temperature (1 km, daily), its anomaly vs. normal (the upwelling signal), and MODIS Kd490 water clarity.',
        '• Sun, moon & solunar — calculated on the phone from the station’s latitude/longitude and date (no network needed).',
      ],
    ),
    _Section(
      Icons.show_chart,
      'Reading the tide chart',
      [
        'The curve is the predicted water height across the day. Dots mark the high (light) and low (dark) tides, and the amber vertical line is the current time. Green bands are solunar feeding periods.',
        'Use the TODAY / WEEK toggle and the < > arrows to move to any day. On future days the Conditions card switches to that day’s forecast (tagged “Forecast · midday”) since live sensor readings only exist for right now.',
      ],
    ),
    _Section(
      Icons.water,
      'Wind tide (water vs. predicted)',
      [
        'Under the Conditions card you may see a line like “Water 0.7 ft below predicted.” That is the wind tide: the difference between the live observed water level and the astronomical tide prediction.',
        'On the Texas coast it matters a lot: sustained north winds push water out of the bays and back-lakes (water runs below prediction), while south winds stack water in (above prediction). A big difference tells you the flats and marsh drains are unusually low or high right now.',
        'It only shows today, on stations that report a live water-level sensor.',
      ],
    ),
    _Section(
      Icons.set_meal,
      'How the fishing score is calculated',
      [
        'The 1–5 star rating is a quick read on how good the bite looks right now. Stars are earned from factors that line up in your favor:',
        '• Moving water — the tide’s rate of change vs. the day’s strongest movement. Fish feed on current, not slack water.',
        '• Solunar timing — being inside a major (or minor) feeding period.',
        '• Wind — lighter wind (under ~10–15 mph) scores higher; blown-out bays score lower.',
        '• Barometer — a falling pressure trend adds a point, since fish often feed ahead of a front.',
        'Future days use a simpler version based on how well the solunar majors line up with the day’s tide changes (the classic lunar-calendar method), since live wind and pressure aren’t known yet.',
        'Best Windows lists today’s top 2–3 time blocks where those factors stack up, and the movement line (e.g. “Incoming — strongest 2–4 PM”) tells you when the tide runs hardest.',
      ],
    ),
    _Section(
      Icons.brightness_3,
      'Solunar, sun & moon',
      [
        'Solunar theory ties fish (and game) activity to the moon’s position. Major periods (~2 hrs, moon overhead/underfoot) are the strongest; minor periods (~1 hr, moonrise/moonset) are secondary.',
        'The Sun/Moon card shows sunrise, sunset, golden hour, and the moon phase with percent illumination — dawn and dusk around a feeding period are prime.',
      ],
    ),
    _Section(
      Icons.notifications_active,
      'Alerts & notifications',
      [
        'Turn on notifications in Settings. All of your saved favorites are enrolled automatically — no need to toggle each one individually (you can still adjust per-station in Settings). Choose how far ahead to be warned (15/30/45/60 min). Available alerts:',
        '• High & Low Tide — a heads-up before each tide change.',
        '• Solunar Major Windows — before each major feeding period.',
        '• Best Fishing Days — one morning alert when today rates 4+ stars.',
        '• Pressure Drops — fires when the barometer is falling (a front approaching, often a strong pre-front bite). Sent once per day per station.',
        '• Upwelling — fires when the satellite water temperature near the station runs well below normal (1.5 °C / ~2.7 °F or more): colder, often nutrient-rich water is moving in. Sent once per day per station.',
        'Alerts are re-scheduled each time the app opens, covering the next 7 days. They run entirely on your phone — no server or account involved.',
        'On Android 12 and later, precise alarm timing requires the "Alarms & Reminders" permission. If you see an amber banner in Settings, tap Fix to grant it — without it, alerts may arrive late.',
      ],
    ),
    _Section(
      Icons.map,
      'Maps',
      [
        'All maps live under the globe icon on a station’s screen:',
        '• Weather map — animated Wind, Waves, Swell, Temperature, Pressure, and Clouds layers, plus a Rain timeline that flows NOAA radar (past 2 hrs) into an 18-hour forecast. Tap anywhere to read the value at that point.',
        '• Seas map — NOAA WaveWatch III offshore significant-wave-height forecast, stepped through the next ~48 hours. Opens on the open Gulf; tap to read wave height in ft/m.',
        '• Water Temp map — three satellite layers: the sea-surface temperature gradient, Upwelling (how far the water runs above/below normal), and Turbidity (clear vs. murky water). The data follows the map as you pan and zoom, and you can tap anywhere to read the exact value at that spot.',
        '• Salinity map — NOAA NGOFS2 hourly surface-salinity loop for Gulf bays.',
        '• Sargassum map — NOAA’s daily coastal seaweed inundation risk.',
      ],
    ),
    _Section(
      Icons.thermostat,
      'Water temp, upwelling & turbidity',
      [
        'The Water Temp map shows satellite sea-surface temperature as a color wash over the water — find breaks and edges where warm and cool water meet; bait and gamefish stack on those lines.',
        'The Upwelling layer maps how far today’s water temperature sits above (red) or below (blue) the long-term normal. A strong blue patch on the coast usually means upwelling — wind has pushed surface water offshore and colder, nutrient-rich water has risen to replace it. That often turns the bite on (bait concentrates) but can also shift fish deeper or off their summer pattern.',
        'When the water near your station runs 1.5 °C (~2.7 °F) or more below normal, the Conditions card shows an “Upwelling likely” note, and the Upwelling alert (if enabled) sends a once-a-day heads-up. A cold-front cooldown can trigger the same signal — either way, expect cooler water than yesterday.',
        'The Turbidity layer is satellite water clarity: blue = clear, cyan = slightly stained, yellow/red = murky. Match it to your tactics — clear water favors natural colors and longer casts; stained water favors dark/loud baits and scent. White gaps are clouds the satellite couldn’t see through (it’s an 8-day composite, so gaps fill as skies clear).',
        'Tap anywhere on any layer to read the value at that exact spot — the water temperature, how far above/below normal it sits, or the clarity with the approximate depth sunlight reaches. The reading is pulled live from the same NOAA grid cell the map color came from; tap the chip to dismiss it.',
        'How the layers are calculated: Water Temp is NASA JPL’s MUR analysis — infrared and microwave satellite passes blended with buoy and ship reports into a 1 km grid, re-computed daily. Upwelling subtracts the long-term average temperature for that spot and day of year from today’s MUR temperature, so its colors show the departure from normal rather than the temperature itself. Turbidity is MODIS Kd490 — how quickly blue-green light (490 nm) dims as it travels down through the water column; the app converts it to the approximate depth sunlight reaches (about 1 ÷ Kd490, shown in the legend), since higher attenuation means murkier water.',
        'Satellite grids update daily (temperature) to every few days (clarity), so treat them as “the latest picture,” not this minute’s reading.',
      ],
    ),
    _Section(
      Icons.flight_takeoff,
      'Before You Fly (drone airspace check)',
      [
        'Tap the takeoff icon in the home screen toolbar to open the Before You Fly screen. It queries four official public data sources at your GPS location to give a complete picture of what applies — no third-party apps, no account, no redirects.',
        'The map shows colored overlays for the entire visible area. Pan and zoom to explore nearby airspace and protected lands; the overlays update as you move.',
        '• Solid red — FAA Prohibited airspace (P): no drone operations under any circumstances.',
        '• Lighter red — FAA Restricted airspace (R): contact the controlling agency before flying.',
        '• Amber/yellow — Active TFR (Temporary Flight Restriction): a time-limited no-fly zone for wildfires, presidential movements, sporting events, emergencies, etc. Changes daily.',
        '• Orange — FAA Warning or Alert area: exercise caution.',
        '• Blue — Controlled airspace (Class B, C, or D): FAA authorization required before flying a drone.',
        '• Green — National Park Service unit (national park, seashore, monument, recreation area, etc.): drones are prohibited in all NPS units under 36 CFR 1.5, regardless of FAA airspace class. A location can be in Class G (uncontrolled) airspace and still be illegal to fly because of the NPS land-management rule.',
        '• Teal — State Park: most states prohibit drone use in state parks, but rules vary. The app flags state parks so you can check that state\'s specific regulations before flying.',
        '• Purple — USFWS National Wildlife Refuge: drones require a Special Use Permit on most refuges, and many explicitly prohibit them. Contact the refuge manager before flying.',
        'Tap anywhere on the map to check airspace at that exact point. A cyan pin drops on the tapped spot and the status card shows the combined result across all four sources. Tap "My Location" to return to your GPS status.',
        'National park and state park data comes from the USGS Protected Areas Database (PAD-US) — the authoritative federal inventory of all protected lands in the US, covering NPS units and state parks nationwide. This screen is for quick reference only — always confirm with the FAA NOTAM system and local park rules before flying.',
      ],
    ),
    _Section(
      Icons.nightlight_round,
      'Night mode',
      [
        'Tap the moon icon in the top bar of the home screen to switch to night mode. It swaps the navy background for pure black and brightens the text and cyan accents, so the screen is easier to read in the dark — handy on the water before dawn or after sunset, with less glare and more contrast.',
        'Your choice is remembered and applies across the whole app until you tap the moon again.',
      ],
    ),
    _Section(
      Icons.directions_car,
      'Android Auto (in the car)',
      [
        'OpenTides also runs on Android Auto — it is the same app, so there is nothing extra to install. When your phone is connected to a compatible car display, OpenTides appears in the car’s app list.',
        '• Pick a favourite station and you get a glanceable, driver-safe view: a tide-chart image for today, the next high and low, live conditions (water temp and wind), the fishing rating with the best bite times and tide movement, and a moon-phase picture with the sun times — when the phone has computed them.',
        '• Add the stations you want first on the phone; they sync to the car automatically, along with the fishing/sun/moon figures the phone computes.',
        'Android Auto only allows simple, safety-approved layouts, so the car view can’t show the full interactive maps or charts from the phone — it’s a focused at-a-glance version. The car screen only runs while you are connected to a car, so it has no effect on the phone app’s battery or speed.',
      ],
    ),
    _Section(
      Icons.tune,
      'Tips',
      [
        '• Switch between Standard (°F, mph, ft) and Metric in Settings.',
        '• Tap the moon icon on the home screen for a high-contrast night mode.',
        '• Tap the takeoff icon (home screen toolbar) to open the Before You Fly screen — colored overlays show restricted and controlled airspace across the map; tap any spot to check airspace at that exact location.',
        '• Tap the star on a station to save it as a favorite; the home screen also finds the nearest stations by GPS.',
        '• “N/A” simply means that station has no sensor for that reading — tides and forecast still work.',
      ],
    ),
  ];
}

class _Section {
  final IconData icon;
  final String title;
  final List<String> body;
  const _Section(this.icon, this.title, this.body);
}
