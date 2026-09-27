import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/kit.dart' show kOverrides, runKit;
import 'package:test/test.dart';

/// `kit link` derives what to link from the pubspecs. The hand-written map it replaced had fallen
/// three packages behind the apps' dependencies without anything noticing.
void main() {
  late Directory repo;
  late Directory kit;

  void write(String path, String text) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() {
    final base = Directory.systemTemp.createTempSync('dev_tool_kit');
    repo = Directory('${base.path}/app')..createSync();
    kit = Directory('${base.path}/kit')..createSync();
    write('${repo.path}/pubspec.yaml', '''
name: app
environment:
  sdk: ^3.13.4
workspace:
  - packages/localization
dependencies:
  flutter:
    sdk: flutter
  localization:
    path: packages/localization
  core_model: ^0.1.1
  aurora_glass:
    git:
      url: https://github.com/zs-dima/aurora_glass.git
      tag_pattern: v{{version}}
    version: ^0.1.7
dev_dependencies:
  aurora_glass_testing:
    git:
      url: https://github.com/zs-dima/aurora_glass.git
      path: packages/aurora_glass_testing
      tag_pattern: v{{version}}
    version: ^0.1.7
  dev_tool:
    git:
      url: https://github.com/zs-dima/dev_tool.git
      tag_pattern: v{{version}}
    version: ^1.0.0
  lints_tool: ^1.1.1
''');
    write('${repo.path}/packages/localization/pubspec.yaml', '''
name: localization
resolution: workspace
dev_dependencies:
  l10n_tool:
    git:
      url: https://github.com/zs-dima/l10n_tool.git
      tag_pattern: v{{version}}
    version: ^0.1.3
''');
    for (final (dir, name) in const <(String, String)>[
      ('core_model', 'core_model'),
      ('aurora_glass', 'aurora_glass'),
      ('aurora_glass/packages/aurora_glass_testing', 'aurora_glass_testing'),
      ('l10n_tool', 'l10n_tool'),
      // A folder with the right name holding a different package is not the dependency.
      ('lints_tool', 'something_else'),
    ]) {
      write('${kit.path}/$dir/pubspec.yaml', 'name: $name\n');
    }
  });
  tearDown(() => repo.parent.deleteSync(recursive: true));

  test('every direct dependency of the root and the members, git by repository, hosted by name', () {
    expect(
      kitDependencies(repo.path).map((d) => '${d.name}:${d.repo}/${d.subpath}'),
      equals(<String>[
        'aurora_glass:aurora_glass/',
        'aurora_glass_testing:aurora_glass/packages/aurora_glass_testing',
        'core_model:core_model/',
        'dev_tool:dev_tool/',
        'l10n_tool:l10n_tool/',
        'lints_tool:lints_tool/',
      ]),
      reason: 'path and sdk dependencies are the repository\'s own and never linked',
    );
  });

  test('link writes the checkouts that exist, as the developer gave the kit directory; unlink removes it', () {
    expect(runKit(<String>['link', '--root', repo.path, '--kit', '../kit']), isZero);
    final overrides = File('${repo.path}/$kOverrides').readAsStringSync();
    expect(
      overrides,
      contains('  aurora_glass_testing:\n    path: ../kit/aurora_glass/packages/aurora_glass_testing\n'),
    );
    expect(
      overrides,
      contains('  l10n_tool:\n    path: ../kit/l10n_tool\n'),
      reason: 'a workspace member\'s dependency counts',
    );
    expect(overrides, isNot(contains('lints_tool')), reason: 'the folder holds another package');
    expect(overrides, isNot(contains('dev_tool')), reason: 'no checkout, nothing written');

    expect(runKit(<String>['unlink', '--root', repo.path]), isZero);
    expect(File('${repo.path}/$kOverrides').existsSync(), isFalse);
  });

  test('link without a kit directory is a usage error; with no matching checkout it fails', () {
    expect(() => runKit(<String>['link', '--root', repo.path]), throwsA(isA<UsageException>()));
    expect(runKit(<String>['link', '--root', repo.path, '--kit', repo.path]), equals(1));
  });

  test('--kit takes a PATH-style list and a repeated flag alike', () {
    final other = Directory('${kit.parent.path}/other')..createSync();
    final separator = Platform.isWindows ? ';' : ':';
    expect(runKit(<String>['link', '--kit', '${other.path}$separator${kit.path}', '--root', repo.path]), isZero);
    final listed = File('${repo.path}/$kOverrides').readAsStringSync();
    expect(runKit(<String>['link', '--kit', other.path, '--kit', kit.path, '--root', repo.path]), isZero);
    expect(File('${repo.path}/$kOverrides').readAsStringSync(), equals(listed));
  });
}
