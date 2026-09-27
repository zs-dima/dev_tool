import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:test/test.dart';

/// The verdict from the report, not the exit code: on 2026-09-14 a suite died at startup, the report
/// recorded `"done": {"success": false}` and `flutter test` exited 0. The first case is that report.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('report_verdict'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<String> lines) {
    final file = File('${dir.path}/$name')..writeAsStringSync(lines.join('\n'));
    return file.path;
  }

  test('a suite that failed to LOAD is a failure, however the process exited', () {
    final path = write('load_failure.json', <String>[
      '{"protocolVersion":"0.1.1","type":"start","time":0}',
      '{"type":"testStart","test":{"id":70,"name":"loading test/journal/home_chips_test.dart"},"time":1}',
      '{"type":"error","testID":70,"error":"Failed to load: Connection closed before test suite loaded.","time":2}',
      '{"type":"testDone","testID":70,"result":"error","skipped":false,"hidden":false,"time":3}',
      '{"type":"done","success":false,"time":4}',
    ]);

    final verdict = reportVerdict(path);

    expect(verdict.ok, isFalse, reason: 'the reporter said success: false');
    expect(
      verdict.problem,
      contains('home_chips_test.dart'),
      reason: 'naming the suite is the difference between a usable failure and a 500 KB file to grep',
    );
  });

  test('a green run is green', () {
    final path = write('green.json', <String>[
      '{"type":"testStart","test":{"id":1,"name":"it works"},"time":1}',
      '{"type":"testDone","testID":1,"result":"success","skipped":false,"hidden":false,"time":2}',
      '{"type":"done","success":true,"time":3}',
    ]);

    expect(reportVerdict(path).ok, isTrue);
  });

  test('a report with NO verdict is a failure, not a pass', () {
    // What a killed process leaves. Reading only "did it say false?" calls this green, which is
    // the same blindness one layer down.
    final path = write('truncated.json', <String>[
      '{"type":"testStart","test":{"id":1,"name":"it works"},"time":1}',
      '{"type":"testDone","testID":1,"result":"success","skipped":false,"hidden":false,"time":2}',
      '{"type":"testStart","test":{"id":2,"name":"it was still runn',
    ]);

    final verdict = reportVerdict(path);

    expect(verdict.ok, isFalse);
    expect(verdict.problem, contains('did not finish'));
  });

  test('no report at all is a failure', () {
    final verdict = reportVerdict('${dir.path}/nothing_here.json');

    expect(verdict.ok, isFalse);
    expect(verdict.problem, contains('no report'));
  });

  test('a hidden testDone does not count against the run', () {
    // `package:test` reports its own loading entries as hidden once they succeed; counting them
    // would make every green run name a failure it did not have.
    final path = write('hidden.json', <String>[
      '{"type":"testStart","test":{"id":1,"name":"loading foo_test.dart"},"time":1}',
      '{"type":"testDone","testID":1,"result":"error","skipped":false,"hidden":true,"time":2}',
      '{"type":"done","success":true,"time":3}',
    ]);

    expect(reportVerdict(path).ok, isTrue);
  });

  test('`done` with success null is a failure: the runner closed before the suite finished', () {
    final verdict = reportVerdict(write('null.json', <String>['{"type":"done","success":null,"time":4}']));
    expect(verdict.ok, isFalse);
    expect(verdict.problem, contains('success: false'));
  });
}
