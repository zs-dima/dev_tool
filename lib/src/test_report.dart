/// The verdict of a `package:test` JSON report.
///
/// An exit code is not a verdict: on 2026-09-14 a suite died at startup, the reporter wrote
/// `"done": {"success": false}` and `flutter test` exited 0.
library;

import 'dart:convert';
import 'dart:io';

/// What a report says about the run that wrote it: [ok], and [problem] when it is not.
typedef ReportVerdict = ({bool ok, String? problem});

/// The verdict recorded in the JSON report at [path]. No report or no `done` event (a run killed
/// before its reporter finished) is a failure.
ReportVerdict reportVerdict(String path) {
  final file = File(path);
  if (!file.existsSync()) return (ok: false, problem: 'no report at $path');

  bool? success;
  final unsuccessful = <String>[];
  final names = <int, String>{};

  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue; // a killed process leaves a half-written last line
    }
    if (decoded is! Map<String, Object?>) continue;

    switch (decoded) {
      case {'type': 'testStart', 'test': {'id': final int id, 'name': final String name}}:
        names[id] = name;

      case {'type': 'testDone', 'testID': final int id, 'result': final String result}
          when result != 'success' && decoded['hidden'] != true:
        unsuccessful.add(names[id] ?? 'test #$id');

      case {'type': 'done', 'success': final bool value}:
        success = value;

      case {'type': 'done'}:
        success = false; // `success: null`: the runner closed before the suite finished
    }
  }

  if (success == null) {
    return (ok: false, problem: 'the report has no `done` event: the run did not finish');
  }
  if (success) return (ok: true, problem: null);

  final named = unsuccessful.take(5).join(', ');
  final rest = unsuccessful.length > 5 ? ' (+${unsuccessful.length - 5} more)' : '';
  return (
    ok: false,
    problem: unsuccessful.isEmpty
        ? 'the report records success: false'
        : 'the report records success: false: $named$rest',
  );
}
