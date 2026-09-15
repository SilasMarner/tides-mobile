#!/usr/bin/env bash
# Builds the F-Droid variant of the tides APK: same source as the Play
# build, minus the `in_app_update` dependency (Google Play Core is a
# proprietary, Play-Services-only library that F-Droid's build scanner
# rejects). This is the same recipe F-Droid's own build server runs from
# the fdroiddata metadata for this app — kept here so it can be tested
# locally before submitting/updating that metadata.
#
# Swaps lib/services/app_update_service.dart for the no-op fdroid stub,
# strips the in_app_update line from pubspec.yaml, builds, then restores
# the working tree via git so the Play build is never affected.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree not clean — commit or stash before building the fdroid variant" >&2
  exit 1
fi

cleanup() {
  git checkout -- pubspec.yaml lib/services/app_update_service.dart
  rm -f pubspec.lock
  git checkout -- pubspec.lock 2>/dev/null || true
}
trap cleanup EXIT

sed -i '/in_app_update:/d' pubspec.yaml
cp lib/services/app_update_service_fdroid.dart lib/services/app_update_service.dart

flutter pub get
flutter build apk --release

echo "F-Droid APK built: build/app/outputs/flutter-apk/app-release.apk"
