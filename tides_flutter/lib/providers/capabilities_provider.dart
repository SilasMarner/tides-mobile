import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/noaa_api.dart';

final stationCapabilitiesProvider =
    FutureProvider<Map<String, Set<String>>>((ref) => fetchCapabilityMap());
