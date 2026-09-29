/// Shared developer tooling for Dart and Flutter repositories.
///
/// The executables are the product (`dart run dev_tool:<name>`); this library exposes their pure
/// parts for tests and for a consumer that wants to call them in-process.
library;

export 'src/build_number.dart' show buildNumber, kPlayCeiling;
export 'src/check_keys.dart' show disallowedKeys;
export 'src/cli.dart' show HelpRequested, UsageException;
export 'src/config.dart' show DevToolConfig, ReleaseClock, kDefaultClock, loadConfig, parseConfig;
export 'src/coverage_summary.dart' show CoverageRow, coverageTable, lineCoverage;
export 'src/kit.dart' show KitDependency, kitDependencies, localCheckout, overridesYaml;
export 'src/release_notes.dart' show storeEntries;
export 'src/release_notes_format.dart' show fit, forStore, kStoreLimit, section;
export 'src/test_report.dart' show ReportVerdict, reportVerdict;
export 'src/test_workspace.dart' show TestKind, TestPackage, testPackages, usesFlutter;
export 'src/workspace.dart' show workspaceMembers;
