/// Runs the tests of every package in a repository and fails unless both the exit code and the JSON
/// report of each run say it passed.
///
/// The packages: the root, every pub workspace member with a `test/` directory, and the directories
/// the root pubspec names under `dev_tool: test: extra:` (a Dart or Flutter package outside the
/// workspace, resolved on its own, or an npm project run with `npm test`). One JSON report per
/// Dart/Flutter package lands in `reports/<name>.json`, where the CI test reporter reads it.
/// Pure-Dart packages run under `dart test`.
///
/// ```sh
/// dart run dev_tool:test_workspace                 # every package: the gate
/// dart run dev_tool:test_workspace --only=ui,core  # just those: says so, never passes as the gate
/// ```
/// Other arguments are forwarded to every `dart test` / `flutter test`.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/test_report.dart';
import 'package:yaml/yaml.dart';

/// How a package's tests run: `dart test`, `flutter test --coverage`, or `npm test` (no JSON report).
enum TestKind { dart, flutter, npm }

/// One package the runner tests. [standalone] packages are not resolved by the root's `pub get`.
typedef TestPackage = ({String name, String path, TestKind kind, bool standalone});

/// Every package under [root] the gate tests, in run order: root, workspace members, extras.
List<TestPackage> testPackages(String root) {
  final pubspec = yamlMap('$root/pubspec.yaml');
  if (pubspec == null) throw UsageException('no readable pubspec.yaml under $root');

  final packages = <TestPackage>[_dartPackage(root, pubspec, standalone: false)];
  final members = pubspec['workspace'];
  if (members is YamlList) {
    for (final member in members.cast<String>()) {
      final memberPubspec = yamlMap('$root/$member/pubspec.yaml');
      if (memberPubspec == null) throw UsageException('workspace member $member has no readable pubspec.yaml');
      packages.add(_dartPackage('$root/$member', memberPubspec, standalone: false));
    }
  }

  final block = pubspec['dev_tool'];
  final test = block is YamlMap ? block['test'] : null;
  final extra = test is YamlMap ? test['extra'] : null;
  if (extra != null && extra is! YamlList) {
    throw const UsageException('pubspec.yaml: dev_tool.test.extra must be a list of directories');
  }
  for (final dir in (extra as YamlList? ?? YamlList()).cast<String>()) {
    final path = '$root/$dir';
    if (yamlMap('$path/pubspec.yaml') case final YamlMap extraPubspec) {
      packages.add(_dartPackage(path, extraPubspec, standalone: true));
    } else if (File('$path/package.json').existsSync()) {
      packages.add((name: dir.split('/').last, path: path, kind: TestKind.npm, standalone: true));
    } else {
      throw UsageException('dev_tool.test.extra: $dir has neither pubspec.yaml nor package.json');
    }
  }
  return packages;
}

TestPackage _dartPackage(String path, YamlMap pubspec, {required bool standalone}) {
  bool uses(String section) {
    final deps = pubspec[section];
    return deps is YamlMap && (deps.containsKey('flutter') || deps.containsKey('flutter_test'));
  }

  final name = pubspec['name'] as String? ?? path.split('/').last;
  final kind = uses('dependencies') || uses('dev_dependencies') ? TestKind.flutter : TestKind.dart;
  return (name: name, path: path, kind: kind, standalone: standalone);
}

/// `test_workspace [--root <dir>] [--only=a,b] [test args...]`: exit 0 only when every package passed.
Future<int> runTestWorkspace(List<String> args) async {
  // Absolute: each package runs with its own folder as the working directory, and the report path
  // is resolved from there.
  final root = Directory(rootOf(args)).resolveSymbolicLinksSync().replaceAll(r'\', '/');
  final only = <String>{
    for (final arg in args)
      if (arg.startsWith('--only='))
        for (final name in arg.substring('--only='.length).split(','))
          if (name.trim().isNotEmpty) name.trim(),
  };
  final testArgs = withoutOptions(args, const <String>{'root'}).where((a) => !a.startsWith('--only=')).toList();

  final packages = testPackages(root);
  final unknown = only.where((name) => !packages.any((package) => package.name == name)).toList();
  if (unknown.isNotEmpty) {
    throw UsageException(
      '--only names no package: ${unknown.join(', ')} (packages: ${packages.map((p) => p.name).join(', ')})',
    );
  }
  _freshReports('$root/reports');

  var failed = false;
  for (final package in packages) {
    if (only.isNotEmpty && !only.contains(package.name)) continue;
    if (package.kind != TestKind.npm && !Directory('${package.path}/test').existsSync()) continue;
    if (!await _run(package, root, testArgs)) failed = true;
  }
  if (only.isNotEmpty) stdout.writeln('--- SCOPED RUN: only ${only.join(', ')} - NOT the full gate ---');
  return failed ? 1 : 0;
}

Future<bool> _run(TestPackage package, String root, List<String> testArgs) async {
  final tool = switch (package.kind) {
    TestKind.dart => 'dart',
    TestKind.flutter => 'flutter',
    TestKind.npm => 'npm',
  };
  stdout.writeln('--- Testing ${package.name} ($tool test) ---');

  if (package.kind == TestKind.npm) {
    // `npm ci` when node_modules is absent or older than the lock.
    final installed = File('${package.path}/node_modules/.package-lock.json');
    final lock = File('${package.path}/package-lock.json');
    final stale =
        !installed.existsSync() ||
        (lock.existsSync() && installed.lastModifiedSync().isBefore(lock.lastModifiedSync()));
    if (stale && await _exec('npm', const <String>['ci'], package.path) != 0) {
      stderr.writeln('--- ${package.name}: npm ci failed ---');
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
    if (package.kind == TestKind.flutter) '--coverage',
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
    if (!removed) {
      for (final stale in reports.listSync().whereType<File>()) {
        try {
          stale.deleteSync();
        } on FileSystemException {
          // a stale report nobody can delete is not a gate failure
        }
      }
    }
  }
  reports.createSync(recursive: true);
}
