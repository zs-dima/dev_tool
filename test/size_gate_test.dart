import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/size_gate.dart' show iec, runSizeGate;
import 'package:test/test.dart';

/// The ceiling in `app.json` must be able to fail: a gate that cannot go red measures nothing.
void main() {
  late Directory root;
  late String bundle;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dev_tool_size');
    File('${root.path}/tool/newapp/app.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"sizeBudgetMb": 3}');
    bundle = (File('${root.path}/app-release.aab')..writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 0))).path;
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('within the app.json budget passes, over it fails, and --budget-mb proves the gate can fail', () {
    expect(runSizeGate(<String>['--aab', bundle, '--root', root.path]), isZero);
    expect(runSizeGate(<String>['--aab', bundle, '--root', root.path, '--budget-mb', '1']), equals(1));
  });

  test('the summary gets the table with the extra rows', () {
    final summary = '${root.path}/summary.md';
    runSizeGate(<String>['--ipa', bundle, '--root', root.path, '--summary', summary, '--row', 'Track=alpha']);
    final table = File(summary).readAsStringSync();
    expect(table, contains('| IPA file (upload) | `2.0MiB`'));
    expect(table, contains('| Track | alpha |'));
  });

  test('exactly one artefact, known flags only', () {
    expect(() => runSizeGate(<String>['--root', root.path]), throwsA(isA<UsageException>()));
    expect(() => runSizeGate(<String>['--aab', bundle, '--ipa', bundle]), throwsA(isA<UsageException>()));
    expect(() => runSizeGate(<String>['--aab', bundle, '--bogus', 'x']), throwsA(isA<UsageException>()));
  });

  test('sizes read in binary units', () {
    expect(iec(512), '512.0B');
    expect(iec(75 * 1024 * 1024 + 300 * 1024), '75.3MiB');
  });
}
