/// Shared developer tooling for standalone Dart and Flutter repositories.
///
/// The executables are the product (`dart run dev_tool:<name>`); this library exposes their pure
/// parts for tests and for a consumer that wants to call them in-process.
library;

export 'src/build_number.dart' show ReleaseClock, buildNumber, kLineEpoch, kPlayCeiling, releaseClock;
export 'src/check_keys.dart' show allowedKeys, disallowedKeys, kDefaultKeys;
export 'src/cli.dart' show UsageException, kAppJson;
export 'src/kit.dart' show KitDependency, kitDependencies, localCheckout, overridesYaml;
export 'src/release_notes.dart' show storeEntries;
export 'src/release_notes_format.dart' show fit, forStore, kStoreLimit, section;
export 'src/test_report.dart' show ReportVerdict, reportVerdict;
export 'src/test_workspace.dart' show TestKind, TestPackage, testPackages;
