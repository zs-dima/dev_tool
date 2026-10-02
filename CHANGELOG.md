# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0]

One repository for the estate's Flutter, Dart and Rust repositories, tied to no family of apps: the
executables read a `dev_tool:` block in `pubspec.yaml`, and the workflows run a repository's own
`just` recipes by name for its codegen, its checks and its release builds. `v1` stays at 1.0.1;
callers move to `@v2` one at a time.

### Removed

- `tool/newapp/app.json`: the release clocks, the size budget and the keys allowlist are
  `dev_tool.release` and `dev_tool.keys` in `pubspec.yaml`; the allowlist is empty unless set.
- `flutter-app-gate.yml`, `flutter-package.yml`, `dart-package.yml`,
  `flutter-app-release-android.yml`, `flutter-app-release-ios.yml`, with their app-line inputs
  (`app-audit`, `l10n-verify`, `unused-keys`, `setup-node`): a repository's own checks are its
  `gate-extra` recipe.
- `size_gate --aab`/`--ipa` (now `--file`); the releases' `SENTRY_DSN` secret (now a line of
  `KEYS_ENV`); `xcrun altool`; the templates' `dependabot.yml` and `dart_test.yaml`; the actionlint
  step that skipped itself where the runner had no actionlint.

### Changed

- Every executable parses its arguments with `package:args` and prints `--help`; a usage error exits 2.
- `test_workspace`: an `sdk: flutter` dependency of any name makes a Flutter package; glob workspace
  members expand as pub expands them; an extra without tests, or two packages with one name, is an
  error; `--only` replaces only its own reports; an npm extra without a lockfile is installed with
  `npm install`; test arguments go after `--`; `--no-coverage` skips coverage.
- `build_number` takes any platform; `check_keys --file`; `size_gate` reports without a budget.
- `kit link` writes the overrides of each standalone extra too, rebasing a relative kit path.
- Generated Dart (`*.*.dart`) is not format-checked and stays as its generator emits it; codegen is
  the repository's `gen` recipe (`dart run build_runner build --workspace`), and the gate compares
  its output, untracked files included, with the committed tree.
- The releases build through the repository's recipe with BUILD_NAME and BUILD_NUMBER; a tag must
  name the pubspec's version; the iOS number is no longer held to a fixed range; iOS uploads with a
  second `xcodebuild -exportArchive` (destination upload) of the same archive.
- DCM's missing-key error no longer fires on Dependabot pull requests, which cannot see secrets.
- `just release` tags and moves the major tag only after CI passed on the release commit.

### Added

- Workflows `flutter-gate.yml`, `dart-gate.yml` (a job per runner in `os`),
  `flutter-release-android.yml`, `flutter-release-ios.yml`, `pub-publish.yml`, `rust-ci.yml`,
  `actions-lint.yml`; actions `format-check`, `gate-probe`, `setup-just`, `rust-toolchain`, `rust-publish`.
- `coverage_summary`: the step summary's coverage table, generated files left out.
- Android JVM unit tests in the Flutter gate where `android/app/src/test` exists, as in
  `takt check`.
- The Renovate preset `default.json` (`github>zs-dima/dev_tool`) with an annotation manager for
  versions pinned outside a manifest.
- Fixtures: a Flutter pub workspace (a member with committed generated code, a standalone extra, a
  browser test, an example app) and a Cargo workspace, both run by CI.

## [1.0.1]

### Changed

- The line's checks in the Flutter app workflows (`dcm`, `l10n-verify`, `app-audit`) are off by
  default; a caller turns on the ones its repository has.
- `dart-package.yml` and `flutter-package.yml` run `publish-check`: the published set free of
  secrets and build output, the version named in CHANGELOG.md.
- `setup-flutter` runs pubspec_generator as a global tool at its latest version after build_runner,
  where the app has `lib/_core/generated/constant/pubspec.yaml.g.dart`.

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
