// F-Droid build stub: same public API as app_update_service.dart, with no
// dependency on the `in_app_update` plugin or Google Play Core. F-Droid
// installs deliver updates through the F-Droid client itself, so in-app
// update checks are simply a no-op here.
//
// scripts/build_fdroid.sh copies this file over app_update_service.dart
// before building, and restores the original afterward.
import 'dart:async';

class AppUpdateCheckResult {
  final bool updateAvailable;
  final bool flexibleUpdateAllowed;
  const AppUpdateCheckResult(this.updateAvailable, this.flexibleUpdateAllowed);
}

class AppUpdateService {
  const AppUpdateService._();

  static Future<AppUpdateCheckResult> checkForUpdate() async =>
      const AppUpdateCheckResult(false, false);

  static Future<bool> startFlexibleUpdate() async => false;

  static Stream<void> get onUpdateDownloaded => const Stream.empty();

  static Future<void> completeFlexibleUpdate() async {}
}
