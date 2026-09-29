/// The `dev_tool:` block of a repository's `pubspec.yaml`: the one place the executables read their
/// settings from. An absent key takes its default; a key of the wrong shape, or one this version
/// does not know, is a [UsageException] naming it: a typo must not pass as a default.
///
/// ```yaml
/// dev_tool:
///   test:
///     extra: [example, worker]   # directories outside the workspace the runner also tests
///   release:
///     size_budget_mb: 90         # the ceiling of a release bundle, MiB
///     android:                   # a clock per platform; absent: minutes since 2020-01-01
///       build_number_base: 1788816828
///       build_number_t0: 1788869018
///   keys: [SENTRY_DSN]           # what the keys file may hold; absent: nothing
/// ```
library;

import 'package:dev_tool/src/cli.dart';

/// A release clock: the build number at [t0] (unix seconds) is [base], and it grows by one per minute.
typedef ReleaseClock = ({int base, int t0});

/// The clock of a platform with no `dev_tool.release.<platform>` entry: minutes since
/// 2020-01-01T00:00:00Z, seven digits until 2039.
const ReleaseClock kDefaultClock = (base: 0, t0: 1577836800);

/// One repository's settings.
final class DevToolConfig {
  /// Creates the settings; every field defaults to "not configured".
  const DevToolConfig({
    this.extras = const <String>[],
    this.clocks = const <String, ReleaseClock>{},
    this.sizeBudgetMb,
    this.keys = const <String>[],
  });

  /// `test.extra`: directories outside the workspace the test runner also tests.
  final List<String> extras;

  /// `release.<platform>`: the release clock of each configured platform.
  final Map<String, ReleaseClock> clocks;

  /// `release.size_budget_mb`: the ceiling of a release bundle, in MiB.
  final int? sizeBudgetMb;

  /// `keys`: the variables the keys file may hold.
  final List<String> keys;

  /// The clock of [platform]; [kDefaultClock] when none is configured.
  ReleaseClock clock(String platform) => clocks[platform] ?? kDefaultClock;
}

/// The settings in `<root>/pubspec.yaml`; the defaults when it has no `dev_tool:` block.
DevToolConfig loadConfig(String root) {
  final pubspec = yamlMap('$root/pubspec.yaml');
  if (pubspec == null) throw UsageException('no readable pubspec.yaml under $root');
  return parseConfig(pubspec['dev_tool']);
}

/// [block], the value of a pubspec's `dev_tool:` key, as settings.
DevToolConfig parseConfig(Object? block) {
  if (block == null) return const DevToolConfig();
  final config = _map(block, 'dev_tool');
  _onlyKeys(config, 'dev_tool', const <String>{'test', 'release', 'keys'});

  var extras = const <String>[];
  if (config['test'] case final Object test) {
    final map = _map(test, 'dev_tool.test');
    _onlyKeys(map, 'dev_tool.test', const <String>{'extra'});
    if (map['extra'] case final Object extra) {
      extras = <String>[
        for (final dir in _strings(extra, 'dev_tool.test.extra', 'a list of directories')) _relativeDir(dir),
      ];
    }
  }

  final clocks = <String, ReleaseClock>{};
  int? sizeBudgetMb;
  if (config['release'] case final Object release) {
    for (final MapEntry(:key, :value) in _map(release, 'dev_tool.release').entries) {
      final path = 'dev_tool.release.$key';
      if (key == 'size_budget_mb') {
        if (value is! int || value <= 0) _bad(path, 'a positive integer (MiB)', value);
        sizeBudgetMb = value;
        continue;
      }
      if (key is! String || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(key)) {
        _bad(path, 'a platform name (lower case, e.g. android) or size_budget_mb', key);
      }
      final clock = _map(value, path);
      _onlyKeys(clock, path, const <String>{'build_number_base', 'build_number_t0'});
      final base = clock['build_number_base'];
      final t0 = clock['build_number_t0'];
      if (base is! int) _bad('$path.build_number_base', 'an integer', base);
      if (t0 is! int) _bad('$path.build_number_t0', 'an integer (unix seconds)', t0);
      clocks[key] = (base: base, t0: t0);
    }
  }

  final keys = config['keys'] == null
      ? const <String>[]
      : _strings(config['keys'], 'dev_tool.keys', 'a list of variable names');

  return DevToolConfig(extras: extras, clocks: clocks, sizeBudgetMb: sizeBudgetMb, keys: keys);
}

Map<Object?, Object?> _map(Object? value, String path) =>
    value is Map<Object?, Object?> ? value : _bad(path, 'a map', value);

List<String> _strings(Object? value, String path, String expected) {
  if (value is! List<Object?> || value.any((item) => item is! String || item.trim().isEmpty)) {
    _bad(path, expected, value);
  }
  return value.cast<String>();
}

void _onlyKeys(Map<Object?, Object?> map, String path, Set<String> known) {
  for (final key in map.keys) {
    if (!known.contains(key)) {
      throw UsageException('pubspec.yaml: $path.$key is not a dev_tool setting (known: ${known.join(', ')})');
    }
  }
}

String _relativeDir(String dir) {
  final path = dir.trim().replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
  if (path.startsWith('/') || RegExp('^[A-Za-z]:').hasMatch(path) || path.split('/').contains('..')) {
    _bad('dev_tool.test.extra', 'directories inside the repository, relative to its root', dir);
  }
  return path;
}

Never _bad(String path, String expected, Object? got) =>
    throw UsageException('pubspec.yaml: $path must be $expected, got ${_describe(got)}');

String _describe(Object? value) => switch (value) {
  null => 'nothing',
  String() => '"$value"',
  Map<Object?, Object?>() => 'a map',
  List<Object?>() => 'a list',
  _ => '$value',
};
