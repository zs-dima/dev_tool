import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/size_gate.dart' show iec, runSizeGate;
import 'package:test/test.dart';

/// The ceiling must be able to fail: a gate that cannot go red measures nothing.
void main() {
  late Directory root;
  late String bundle;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dev_tool_size');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: app\ndev_tool:\n  release:\n    size_budget_mb: 3\n');
    bundle = (File('${root.path}/app-release.aab')..writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 0))).path;
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('within the pubspec budget passes; --budget-mb overrides it', () {
    expect(runSizeGate(<String>['--file', bundle, '--root', root.path]), isZero);
    expect(runSizeGate(<String>['--file', bundle, '--root', root.path, '--budget-mb', '5']), isZero);
  });

  test('over budget exits 1 with a GitHub error annotation', () async {
    // A child process: the annotation must land in the captured stderr, not in this job's log, where
    // GitHub would render it as an error on a green run.
    final run = await Process.run('dart', <String>[
      '${Directory.current.path}/bin/size_gate.dart',
      '--file',
      bundle,
      '--budget-mb',
      '1',
    ], runInShell: Platform.isWindows);
    expect(run.exitCode, equals(1));
    expect(run.stderr.toString(), contains('::error::app-release.aab is 2097152 bytes'));
  });

  test('the summary gets the table with the extra rows; any file type is measured', () {
    final ipa = (File('${root.path}/Runner.ipa')..writeAsBytesSync(List<int>.filled(1024, 0))).path;
    final summary = '${root.path}/summary.md';
    runSizeGate(<String>['--file', ipa, '--root', root.path, '--summary', summary, '--row', 'Track=alpha']);
    final table = File(summary).readAsStringSync();
    expect(table, contains('| File | `Runner.ipa` |'));
    expect(table, contains('| Size | `1.0KiB` (1024 bytes) |'));
    expect(table, contains('| Track | alpha |'));
  });

  test('a file and known flags are required; without a budget the size is reported, not gated', () {
    expect(() => runSizeGate(<String>['--root', root.path]), throwsA(isA<UsageException>()));
    expect(() => runSizeGate(<String>['--file', bundle, '--bogus', 'x']), throwsA(isA<UsageException>()));
    expect(() => runSizeGate(<String>['--file', bundle, '--budget-mb', '0']), throwsA(isA<UsageException>()));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    final summary = '${root.path}/summary.md';
    expect(runSizeGate(<String>['--file', bundle, '--root', root.path, '--summary', summary]), isZero);
    expect(File(summary).readAsStringSync(), contains('| Budget | none |'));
  });

  test('sizes read in binary units', () {
    expect(iec(512), '512.0B');
    expect(iec(75 * 1024 * 1024 + 300 * 1024), '75.3MiB');
  });
}
