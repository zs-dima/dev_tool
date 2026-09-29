import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/coverage_summary.dart' show runCoverageSummary;
import 'package:test/test.dart';

/// The step summary's coverage table: per package, generated files left out, a total when there is
/// more than one package.
void main() {
  const lcov = r'''
SF:lib/src/model.dart
DA:1,1
LF:10
LH:8
end_of_record
SF:lib/src/model.g.dart
LF:40
LH:0
end_of_record
SF:C:\app\lib\view.dart
LF:10
LH:2
end_of_record
''';

  test('lines of hand-written files are summed; *.*.dart files are left out', () {
    expect(lineCoverage(lcov), (found: 20, hit: 10));
  });

  test('the table has a row per measured package and a total', () {
    final table = coverageTable(const <CoverageRow>[
      (name: 'app', found: 20, hit: 10),
      (name: 'core', found: 5, hit: 5),
      (name: 'empty', found: 0, hit: 0),
    ])!;
    expect(table, contains('| `app` | 20 | 10 | 50.0% |'));
    expect(table, contains('| `core` | 5 | 5 | 100.0% |'));
    expect(table, isNot(contains('empty')));
    expect(table, contains('| **total** | **25** | **15** | **60.0%** |'));
    expect(coverageTable(const <CoverageRow>[(name: 'app', found: 0, hit: 0)]), isNull);
  });

  test('the executable appends the table to --summary', () {
    final root = Directory.systemTemp.createTempSync('dev_tool_coverage');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    File('${root.path}/coverage/lcov.info')
      ..createSync(recursive: true)
      ..writeAsStringSync(lcov);
    final summary = File('${root.path}/summary.md')..writeAsStringSync('### Before\n');
    expect(runCoverageSummary(<String>['--root', root.path, '--summary', summary.path]), isZero);
    expect(summary.readAsStringSync(), startsWith('### Before\n### Coverage'));
    expect(summary.readAsStringSync(), contains('| `app` | 20 | 10 | 50.0% |'));
  });
}
