import 'dart:convert';

class NotificationPrefs {
  final bool enabled;
  final int leadMinutes;        // 15, 30, 45, or 60
  final bool notifyTides;       // hi/lo tide events
  final bool notifySolunarMajor; // major feeding windows
  final bool notifyFishing;     // fishing rating 4+ stars
  final bool notifyPressureDrop; // barometric drop = approaching front
  final bool notifyUpwelling;   // SST well below normal = upwelling signal
  final Set<String> stations;   // station IDs with notifications on

  const NotificationPrefs({
    this.enabled = false,
    this.leadMinutes = 30,
    this.notifyTides = true,
    this.notifySolunarMajor = true,
    this.notifyFishing = true,
    this.notifyPressureDrop = true,
    this.notifyUpwelling = true,
    this.stations = const {},
  });

  NotificationPrefs copyWith({
    bool? enabled,
    int? leadMinutes,
    bool? notifyTides,
    bool? notifySolunarMajor,
    bool? notifyFishing,
    bool? notifyPressureDrop,
    bool? notifyUpwelling,
    Set<String>? stations,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
        notifyTides: notifyTides ?? this.notifyTides,
        notifySolunarMajor: notifySolunarMajor ?? this.notifySolunarMajor,
        notifyFishing: notifyFishing ?? this.notifyFishing,
        notifyPressureDrop: notifyPressureDrop ?? this.notifyPressureDrop,
        notifyUpwelling: notifyUpwelling ?? this.notifyUpwelling,
        stations: stations ?? this.stations,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'leadMinutes': leadMinutes,
        'notifyTides': notifyTides,
        'notifySolunarMajor': notifySolunarMajor,
        'notifyFishing': notifyFishing,
        'notifyPressureDrop': notifyPressureDrop,
        'notifyUpwelling': notifyUpwelling,
        'stations': stations.toList(),
      };

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
        enabled: j['enabled'] as bool? ?? false,
        leadMinutes: j['leadMinutes'] as int? ?? 30,
        notifyTides: j['notifyTides'] as bool? ?? true,
        notifySolunarMajor: j['notifySolunarMajor'] as bool? ?? true,
        notifyFishing: j['notifyFishing'] as bool? ?? true,
        notifyPressureDrop: j['notifyPressureDrop'] as bool? ?? true,
        notifyUpwelling: j['notifyUpwelling'] as bool? ?? true,
        stations: Set<String>.from(
            (j['stations'] as List<dynamic>? ?? []).cast<String>()),
      );

  static NotificationPrefs fromJsonString(String s) =>
      NotificationPrefs.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());
}
