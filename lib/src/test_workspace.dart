/// Runs the tests of every package in a repository and fails unless both the exit code and the JSON
/// report of each run say it passed.
///
/// The packages: the root, every pub workspace member with a `test/` directory, and the directories
/// `dev_tool.test.extra` names (a Dart or Flutter package outside the workspace, resolved on its own,
/// or an npm project run with `npm test`). One JSON report per Dart package lands in
/// `reports/<name>.json`, where the CI test reporter reads it.
///
/// ```sh
/// dart run dev_tool:test_workspace                   # every package: the gate
/// dart run dev_tool:test_workspace --only ui,core    # just those: says so, never passes as the gate
/// dart run dev_tool:test_workspace -- --tags rig     # everything after -- goes to every test run
/// ```
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/config.dart';
import 'package:dev_tool/src/test_report.dart';
import 'package:dev_tool/src/workspace.dart';
import 'package:yaml/yaml.dart';

/// How a package's tests run: `dart test`, `flutter test`, or `npm test` (no JSON report).
enum TestKind { dart, flutter, npm }

/// One package the runner tests. [standalone] packages are not resolved by the root's `pub get`.
typedef TestPackage = ({String name, String path, TestKind kind, bool standalone});

/// Every package under [root] the runner knows, in run order: root, workspace members, extras.
/// Two packages with one name are an error: their reports would overwrite each other.
List<TestPackage> testPackages(String root) {
  final pubspec = yamlMap('$root/pubspec.yaml');
  if (pubspec == null) throw UsageException('no readable pubspec.yaml under $root');
  final config = parseConfig(pubspec['dev_tool']);

  final packages = <TestPackage>[_dartPackage(root, pubspec, standalone: false)];
  for (final member in workspaceMembers(root, pubspec)) {
    final memberPubspec = yamlMap('$root/$member/pubspec.yaml');
    if (memberPubspec == null) throw UsageException('workspace member $member has no readable pubspec.yaml');
    packages.add(_dartPackage('$root/$member', memberPubspec, standalone: false));
  }
  for (final dir in config.extras) {
    final path = '$root/$dir';
    if (yamlMap('$path/pubspec.yaml') case final YamlMap extraPubspec) {
      // Listed means tested: an extra that lost its tests must not leave the gate silently.
      if (!Directory('$path/test').existsSync()) {
        throw UsageException('dev_tool.test.extra: $dir has no test/ directory');
      }
      packages.add(_dartPackage(path, extraPubspec, standalone: true));
    } else if (File('$path/package.json').existsSync()) {
      packages.add((name: dir.split('/').last, path: path, kind: TestKind.npm, standalone: true));
    } else {
      throw UsageException('dev_tool.test.extra: $dir has neither pubspec.yaml nor package.json');
    }
  }

  final seen = <String, String>{};
  for (final package in packages) {
    if (seen[package.name] case final String other) {
      throw UsageException('two packages are named ${package.name} ($other, ${package.path}): rename one');
    }
    seen[package.name] = package.path;
  }
  return packages;
}

/// Whether [pubspec] depends on the Flutter SDK directly: an `sdk: flutter` entry among its
/// dependencies or dev_dependencies. A package that reaches Flutter only through another package runs
/// under `dart test` and fails to load; the fix is a direct `flutter` dependency.
bool usesFlutter(YamlMap pubspec) => <Object?>[pubspec['dependencies'], pubspec['dev_dependencies']].any(
  (deps) => deps is YamlMap && deps.values.any((spec) => spec is YamlMap && spec['sdk'] == 'flutter'),
);

TestPackage _dartPackage(String path, YamlMap pubspec, {required bool standalone}) => (
  name: pubspec['name'] as String? ?? path.split('/').last,
  path: path,
  kind: usesFlutter(pubspec) ? TestKind.flutter : TestKind.dart,
  standalone: standalone,
);

const String _synopsis =
    'test_workspace [--root <dir>] [--only <package>[,<package>...]] [--no-coverage] [-- <test arguments>]';

/// Exit 0 only when every package passed; 1 when one failed; 2 on a usage error.
Future<int> runTestWorkspace(List<String> args) async {
  final parser = commandParser()
    ..addMultiOption('only', valueHelp: 'package', help: 'Test only these packages. Such a run is not the gate.')
    ..addFlag('coverage', defaultsTo: true, help: 'Collect coverage in Flutter packages (coverage/lcov.info).');
  final results = parseArgs(parser, args, _synopsis, maxRest: null);
  final root = rootOf(results);
  final only = <String>{
    for (final name in results.multiOption('only'))
      if (name.trim().isNotEmpty) name.trim(),
  };

  final packages = testPackages(root);
  final unknown = only.where((name) => !packages.any((package) => package.name == name)).toList();
  if (unknown.isNotEmpty) {
    throw UsageException(
      '--only names no package: ${unknown.join(', ')} (packages: ${packages.map((p) => p.name).join(', ')})',
    );
  }
  // A scoped run replaces only its own reports: the reporter must not lose the other packages' verdicts.
  if (only.isEmpty) {
    _freshReports('$root/reports');
  } else {
    Directory('$root/reports').createSync(recursive: true);
    for (final name in only) {
      _deleteFile(File('$root/reports/$name.json'));
    }
  }

  var failed = false;
  for (final package in packages) {
    if (only.isNotEmpty && !only.contains(package.name)) continue;
    if (package.kind != TestKind.npm && !package.standalone && !Directory('${package.path}/test').existsSync()) {
      continue;
    }
    if (!await _run(package, root, results.rest, coverage: results.flag('coverage'))) failed = true;
  }
  if (only.isNotEmpty) stdout.writeln('--- SCOPED RUN: only ${only.join(', ')} - NOT the full gate ---');
  return failed ? 1 : 0;
}

Future<bool> _run(TestPackage package, String root, List<String> testArgs, {required bool coverage}) async {
  final tool = package.kind.name;
  stdout.writeln('--- Testing ${package.name} ($tool test) ---');

  if (package.kind == TestKind.npm) {
    if (!await _npmInstall(package.path)) {
      stderr.writeln('--- ${package.name}: npm install failed ---');
      return false;
    }
    return await _exec('npm', const <String>['test'], package.path) == 0;
  }

  if (package.standalone && await _exec(tool, const <String>['pub', 'get'], package.path) != 0) {
    stderr.writeln('--- ${package.name}: pub get failed ---');
    return false;
  }

  final report = '$root/reports/${package.name}.json';
  final code = await _exec(tool, <String>[
    'test',
    if (package.kind == TestKind.flutter && coverage) '--coverage',
    '--test-randomize-ordering-seed=random',
    '--file-reporter',
    'json:$report',
    ...testArgs,
  ], package.path);
  // `flutter test` exits 0 on a run its own reporter marked failed (2026-09-14).
  final verdict = reportVerdict(report);
  if (code == 0 && !verdict.ok) stderr.writeln('--- ${package.name}: exit 0, but ${verdict.problem} ---');
  return code == 0 && verdict.ok;
}

/// `npm ci` when `node_modules` is absent or older than the lock; `npm install` when there is no lock.
Future<bool> _npmInstall(String path) async {
  final lock = File('$path/package-lock.json');
  if (!lock.existsSync()) {
    return Directory('$path/node_modules').existsSync() || await _exec('npm', const <String>['install'], path) == 0;
  }
  final installed = File('$path/node_modules/.package-lock.json');
  final stale = !installed.existsSync() || installed.lastModifiedSync().isBefore(lock.lastModifiedSync());
  return !stale || await _exec('npm', const <String>['ci'], path) == 0;
}

Future<int> _exec(String tool, List<String> args, String workingDirectory) async {
  final process = await Process.start(
    tool,
    args,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
    mode: .inheritStdio,
  );
  return await process.exitCode;
}

/// Empties `reports/` so a stale report of a removed package never reaches the reporter. Retried,
/// then file by file: on Windows a just-exited test process can hold the directory (2026-09-20).
void _freshReports(String path) {
  final reports = Directory(path);
  if (reports.existsSync()) {
    var removed = false;
    for (var attempt = 0; attempt < 5 && !removed; attempt++) {
      try {
        reports.deleteSync(recursive: true);
        removed = true;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 200));
      }
    }
    if (!removed) reports.listSync().whereType<File>().forEach(_deleteFile);
  }
  reports.createSync(recursive: true);
}

void _deleteFile(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // a stale report nobody can delete is not a gate failure
  }
}
