import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/test_workspace.dart' show runTestWorkspace;
import 'package:test/test.dart';

/// Which packages the gate tests, and how. Running them is proven on real repositories; what this
/// pins is the discovery, because a package the runner never finds is a suite that silently left
/// the gate.
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

  test('an extra that is neither a Dart package nor an npm project is an error, not a skip', () {
    write('pubspec.yaml', 'name: app\ndev_tool:\n  test:\n    extra:\n      - nothing_here\n');
    expect(() => testPackages(root.path), throwsA(isA<UsageException>()));
  });

  test('a repository without a workspace is its root package alone', () {
    write('pubspec.yaml', 'name: core_model\n');
    expect(testPackages(root.path).single.kind, TestKind.dart);
  });

  test('--only naming no package is refused instead of running nothing', () async {
    write('pubspec.yaml', '''
name: app
dependencies:
  flutter:
    sdk: flutter
''');
    write('test/app_test.dart', 'void main() {}');
    expect(
      () => runTestWorkspace(<String>['--root', root.path, '--only=croe']),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('croe'))),
    );
  });
}
