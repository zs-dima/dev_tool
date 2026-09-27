@Timeout(Duration(minutes: 5)) // a temporary package: pub get and the first compile of `dart test`
library;

import 'dart:io';

import 'package:dev_tool/src/test_workspace.dart';
import 'package:test/test.dart';

/// The runner end to end on a real package: the exit code follows the suite, the report lands under
/// the root, and a relative `--root` works from another working directory.
void main() {
  late Directory root;

  void write(String path, String text) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

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
    // The executable from another working directory: the current directory is process-wide, so
    // the test does not change it.
    final name = root.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final run = await Process.run(
      'dart',
      <String>['${Directory.current.path}/bin/test_workspace.dart', '--root', name],
      workingDirectory: root.parent.path,
      runInShell: Platform.isWindows,
    );
    expect(run.exitCode, isZero, reason: '${run.stdout}${run.stderr}');
    expect(File('${root.path}/reports/e2e.json').existsSync(), isTrue);
  });

  test('a failing test exits 1', () async {
    write('test/fail_test.dart', '''
import 'package:test/test.dart';
void main() => test('fails', () => expect(1, 2));
''');
    addTearDown(() => File('${root.path}/test/fail_test.dart').deleteSync()); // the order is random
    expect(await runTestWorkspace(<String>['--root', root.path]), equals(1));
  });
}
