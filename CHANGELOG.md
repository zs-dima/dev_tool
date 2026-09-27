# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0]

### Added

- `test_workspace`: every package's tests with the JSON-report verdict; extras declared under
  `dev_tool: test: extra:` (a standalone Dart package or an npm project). From the app line's runner
  (BreakerSonar, FlickerGauge's Worker extension, aurora_glass's gallery).
- `kit link|unlink`: `pubspec_overrides.yaml` for local kit checkouts, the set derived from the
  pubspecs (the apps' hand-written map had fallen three packages behind).
- `build_number`: one release clock for the recipe and the workflow; the local build used seconds
  while CI used minutes until now.
- `check_keys`: `config/keys.env` against an allowlist in `app.json`.
- `size_gate`, `release_notes` (DoctorNoise's `--out`; en-US from the changelog, other locales from a
  written whatsnew.txt).
- Reusable workflows: `flutter-app-gate`, `flutter-app-release-android`, `flutter-app-release-ios`,
  `dart-package`, `flutter-package`, `test-report`; composite actions `setup-flutter`, `gate-checks`.
- Templates for `flutter-app`, `dart-package`, `rust`.
