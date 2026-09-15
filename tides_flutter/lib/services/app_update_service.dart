// Play Store implementation, backed by the `in_app_update` plugin (which
// wraps Google Play Core's app-update API). This file is swapped out for
// app_update_service_fdroid.dart by scripts/build_fdroid.sh when building
// for F-Droid, since Play Core is a proprietary, Play-Services-only library
// that F-Droid's build scanner will reject.
import 'dart:async';

import 'package:in_app_update/in_app_update.dart';

class AppUpdateCheckResult {
  final bool updateAvailable;
  final bool flexibleUpdateAllowed;
  const AppUpdateCheckResult(this.updateAvailable, this.flexibleUpdateAllowed);
}

class AppUpdateService {
  const AppUpdateService._();

  static Future<AppUpdateCheckResult> checkForUpdate() async {
    final info = await InAppUpdate.checkForUpdate();
    return AppUpdateCheckResult(
      info.updateAvailability == UpdateAvailability.updateAvailable,
      info.flexibleUpdateAllowed,
    );
  }

  /// Starts a flexible (background) update download. Returns true once the
  /// download completes successfully.
  static Future<bool> startFlexibleUpdate() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    return result == AppUpdateResult.success;
  }

  /// Fires once when a previously-started flexible update finishes
  /// downloading and is ready to install.
  static Stream<void> get onUpdateDownloaded => InAppUpdate.installUpdateListener
      .where((status) => status == InstallStatus.downloaded)
      .map((_) {});

  static Future<void> completeFlexibleUpdate() =>
      InAppUpdate.completeFlexibleUpdate();
}
