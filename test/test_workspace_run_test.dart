@Timeout(Duration(minutes: 5)) // a temporary package: pub get and the first compile of `dart test`
library;

import 'dart:io';

import 'package:dev_tool/src/test_report.dart';
import 'package:test/test.dart';

/// The runner end to end on a real package, as a child process: the exit code follows the suite, the
/// report lands under the root, a relative `--root` works from another working directory, and an npm
/// extra without a lockfile is installed and tested.
void main() {
  late Directory root;

  void write(String path, String text) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<ProcessResult> runner(List<String> args, {String? workingDirectory}) => Process.run(
    'dart',
    <String>['${Directory.current.path}/bin/test_workspace.dart', ...args],
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('dev_tool_run');
    write('pubspec.yaml', '''
name: e2e
environment:
  sdk: ^3.13.4
dev_dependencies:
  test: ^1.26.3
''');
    write('test/pass_test.dart', '''
import 'package:test/test.dart';
void main() => test('passes', () => expect(1, 1));
''');
    final get = await Process.run(
      'dart',
      <String>['pub', 'get'],
      workingDirectory: root.path,
      runInShell: Platform.isWindows,
    );
    expect(get.exitCode, isZero, reason: get.stderr.toString());
  });
  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle Windows still holds is one stale temp folder, not a failed test
    }
  });

  test('a green package exits 0 with its report under the root, from a relative --root', () async {
    final name = root.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final run = await runner(<String>['--root', name], workingDirectory: root.parent.path);
    expect(run.exitCode, isZero, reason: '${run.stdout}${run.stderr}');
    expect(File('${root.path}/reports/e2e.json').existsSync(), isTrue);
  });

  test('a failing test exits 1', () async {
    write('test/fail_test.dart', '''
import 'package:test/test.dart';
void main() => test('fails', () => expect(1, 2));
''');
    addTearDown(() => File('${root.path}/test/fail_test.dart').deleteSync()); // the order is random
    final run = await runner(<String>['--root', root.path]);
    expect(run.exitCode, equals(1), reason: '${run.stdout}${run.stderr}');
    expect(reportVerdict('${root.path}/reports/e2e.json').ok, isFalse);
  });

  test('arguments after -- reach the test run', () async {
    // `--name` selects no test: package:test exits 79 ("No tests match"), so the flag arrived.
    final run = await runner(<String>['--root', root.path, '--', '--name', 'no such test']);
    expect(run.exitCode, equals(1), reason: '${run.stdout}${run.stderr}');
    expect('${run.stdout}${run.stderr}', contains('No tests match'));
  });

  test('an npm extra without a lockfile is installed and tested', () async {
    final pubspec = File('${root.path}/pubspec.yaml');
    final original = pubspec.readAsStringSync();
    addTearDown(() => pubspec.writeAsStringSync(original));
    pubspec.writeAsStringSync('$original\ndev_tool:\n  test:\n    extra: [worker]\n');
    write('worker/package.json', '{"name": "worker", "private": true, "scripts": {"test": "node --version"}}');
    final run = await runner(<String>['--root', root.path, '--only', 'worker']);
    expect(run.exitCode, isZero, reason: '${run.stdout}${run.stderr}');
    expect(File('${root.path}/worker/package-lock.json').existsSync(), isTrue, reason: 'npm install ran');
  });
}
