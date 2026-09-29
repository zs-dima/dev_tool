import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/test_workspace.dart' show runTestWorkspace;
import 'package:test/test.dart';

/// Which packages the gate tests, and how. Running them is proven end to end in
/// `test_workspace_run_test.dart`; what this pins is the discovery, because a package the runner never
/// finds is a suite that silently left the gate.
void main() {
  late Directory root;

  void write(String path, String text) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() => root = Directory.systemTemp.createTempSync('dev_tool_workspace'));
  tearDown(() => root.deleteSync(recursive: true));

  test('root, workspace members and the declared extras, each with how it runs', () {
    write('pubspec.yaml', '''
name: app
workspace:
  - packages/dsp_core
  - packages/localization
dependencies:
  flutter:
    sdk: flutter
dev_tool:
  test:
    extra:
      - example
      - worker
''');
    write('packages/dsp_core/pubspec.yaml', 'name: dsp_core\nresolution: workspace\n');
    write('packages/localization/pubspec.yaml', '''
name: localization
resolution: workspace
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
    write('example/pubspec.yaml', 'name: gallery\ndependencies:\n  flutter:\n    sdk: flutter\n');
    write('example/test/gallery_test.dart', 'void main() {}');
    write('worker/package.json', '{"scripts": {"test": "vitest run"}}');

    final packages = testPackages(root.path);
    expect(packages.map((p) => '${p.name}:${p.kind.name}:${p.standalone}'), <String>[
      'app:flutter:false',
      'dsp_core:dart:false',
      'localization:flutter:false',
      'gallery:flutter:true',
      'worker:npm:true',
    ]);
  });

  test('any sdk: flutter dependency makes a Flutter package, not only flutter and flutter_test', () {
    write('pubspec.yaml', 'name: l10n\ndependencies:\n  flutter_localizations:\n    sdk: flutter\n');
    expect(testPackages(root.path).single.kind, TestKind.flutter);
  });

  test('a glob member expands, as pub expands it, to the directories holding a pubspec', () {
    write('pubspec.yaml', 'name: app\nworkspace:\n  - packages/*\n');
    write('packages/b/pubspec.yaml', 'name: b\nresolution: workspace\n');
    write('packages/a/pubspec.yaml', 'name: a\nresolution: workspace\n');
    Directory('${root.path}/packages/notes').createSync();
    expect(testPackages(root.path).map((p) => p.name), <String>['app', 'a', 'b']);
  });

  test('an extra that is neither a Dart package nor an npm project is an error, not a skip', () {
    write('pubspec.yaml', 'name: app\ndev_tool:\n  test:\n    extra:\n      - nothing_here\n');
    expect(() => testPackages(root.path), throwsA(isA<UsageException>()));
  });

  test('an extra without tests is an error: listed means tested', () {
    write('pubspec.yaml', 'name: app\ndev_tool:\n  test:\n    extra: [example]\n');
    write('example/pubspec.yaml', 'name: example\n');
    expect(
      () => testPackages(root.path),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('no test/'))),
    );
  });

  test('two packages with one name are refused: their reports would overwrite each other', () {
    write('pubspec.yaml', 'name: app\nworkspace:\n  - packages/app\n');
    write('packages/app/pubspec.yaml', 'name: app\nresolution: workspace\n');
    expect(
      () => testPackages(root.path),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('two packages are named app'))),
    );
  });

  test('a repository without a workspace is its root package alone', () {
    write('pubspec.yaml', 'name: core_model\n');
    expect(testPackages(root.path).single.kind, TestKind.dart);
  });

  test('--only naming no package is refused instead of running nothing', () async {
    write('pubspec.yaml', 'name: app\n');
    write('test/app_test.dart', 'void main() {}');
    await expectLater(
      () => runTestWorkspace(<String>['--root', root.path, '--only=croe']),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('croe'))),
    );
  });

  test('a scoped run keeps the reports of the packages it did not run; the full run clears them', () async {
    // Neither package has a test/ directory, so nothing runs and only the report handling is seen.
    write('pubspec.yaml', 'name: app\nworkspace:\n  - packages/core\n');
    write('packages/core/pubspec.yaml', 'name: core\nresolution: workspace\n');
    write('reports/core.json', '{}');
    write('reports/app.json', '{}');

    expect(await runTestWorkspace(<String>['--root', root.path, '--only', 'app']), isZero);
    expect(File('${root.path}/reports/core.json').existsSync(), isTrue, reason: 'not in the scope');
    expect(File('${root.path}/reports/app.json').existsSync(), isFalse, reason: 'in the scope: replaced');

    expect(await runTestWorkspace(<String>['--root', root.path]), isZero);
    expect(File('${root.path}/reports/core.json').existsSync(), isFalse);
  });

  test('an unknown option is refused rather than forwarded; arguments after -- are forwarded', () async {
    write('pubspec.yaml', 'name: app\n');
    await expectLater(
      () => runTestWorkspace(<String>['--root', root.path, '--tags', 'rig']),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('--tags'))),
    );
    expect(await runTestWorkspace(<String>['--root', root.path, '--', '--tags', 'rig']), isZero);
  });
}
