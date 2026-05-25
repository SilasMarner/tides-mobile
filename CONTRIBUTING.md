# Contributing to Tides

Thanks for your interest in contributing. This is a personal project but pull requests for bug fixes and improvements are welcome.

## Getting started

1. Fork the repository
2. Create a branch: `git checkout -b fix/your-description`
3. Make your changes
4. Test on a real device or emulator
5. Open a pull request

## Development setup

### Prerequisites
- Flutter SDK 3.44+
- Android SDK with API 35+
- Java 17
- An Android device or emulator

### Running the app

```bash
cd tides_flutter
flutter pub get
flutter run
```

### Building a release APK

```bash
flutter build apk --release
```

## Code style

- Follow standard [Dart/Flutter style guidelines](https://dart.dev/guides/language/effective-dart/style)
- Run `flutter analyze` before submitting — no new warnings
- Run `flutter format .` to format code
- Keep widgets small and focused; extract to `widgets/` when reusable
- New providers go in `providers/`, new API calls go in `services/`

## What to contribute

Good candidates:
- Bug fixes with a clear reproduction case
- Performance improvements
- Additional NOAA data fields that are already returned by the API
- UI polish that stays consistent with the dark Material 3 theme

Please open an issue first for larger changes (new screens, new API integrations) so we can discuss the approach before you invest time in implementation.

## Pull request guidelines

- One logical change per PR
- Include a brief description of what changed and why
- Test on a physical device if at all possible — emulator behavior can differ
- Screenshots are helpful for UI changes

## Reporting bugs

Open a GitHub issue with:
- Android version and device model
- App version (visible in About screen)
- Steps to reproduce
- Expected vs actual behavior
