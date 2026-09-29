/// The line coverage of every Dart package the test runner tested, from each package's
/// `coverage/lcov.info`, as a Markdown table on stdout and, with `--summary`, appended to that file
/// (CI passes `$GITHUB_STEP_SUMMARY`). Generated files (`*.*.dart`) are left out: their lines
/// measure the generator, not the tests.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/test_workspace.dart';

/// One package's measured lines.
typedef CoverageRow = ({String name, int found, int hit});

final RegExp _generated = RegExp(r'\.[^/\\]*\.dart$');

/// The lines found and hit in [lcov], an lcov tracefile, summed over its hand-written files.
({int found, int hit}) lineCoverage(String lcov) {
  var found = 0;
  var hit = 0;
  var counted = true;
  for (final raw in lcov.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      counted = !_generated.hasMatch(line.substring(3));
    } else if (counted && line.startsWith('LF:')) {
      found += int.tryParse(line.substring(3)) ?? 0;
    } else if (counted && line.startsWith('LH:')) {
      hit += int.tryParse(line.substring(3)) ?? 0;
    }
  }
  return (found: found, hit: hit);
}

/// The Markdown table of [rows], with a total when there is more than one; `null` when no row
/// measured a line.
String? coverageTable(List<CoverageRow> rows) {
  final measured = rows.where((row) => row.found > 0).toList();
  if (measured.isEmpty) return null;
  String percent(int hit, int found) => '${(hit * 100 / found).toStringAsFixed(1)}%';
  final table = StringBuffer()
    ..writeln('### Coverage')
    ..writeln()
    ..writeln('| Package | Lines | Covered | % |')
    ..writeln('|---|---:|---:|---:|');
  for (final row in measured) {
    table.writeln('| `${row.name}` | ${row.found} | ${row.hit} | ${percent(row.hit, row.found)} |');
  }
  if (measured.length > 1) {
    final found = measured.fold(0, (sum, row) => sum + row.found);
    final hit = measured.fold(0, (sum, row) => sum + row.hit);
    table.writeln('| **total** | **$found** | **$hit** | **${percent(hit, found)}** |');
  }
  return table.toString();
}

/// `coverage_summary [--root <dir>] [--summary <file>]`: exit 0, with or without a measurement.
int runCoverageSummary(List<String> args) {
  final parser = commandParser()
    ..addOption('summary', valueHelp: 'file', help: r'Append the table to this file (CI: $GITHUB_STEP_SUMMARY).');
  final results = parseArgs(parser, args, 'coverage_summary [--root <dir>] [--summary <file>]');
  final rows = <CoverageRow>[
    for (final package in testPackages(rootOf(results)))
      if (File('${package.path}/coverage/lcov.info') case final lcov when lcov.existsSync())
        if (lineCoverage(lcov.readAsStringSync()) case (:final found, :final hit))
          (name: package.name, found: found, hit: hit),
  ];
  final table = coverageTable(rows);
  if (table == null) {
    stderr.writeln('No coverage/lcov.info measured a line: run the tests with coverage first.');
    return 0;
  }
  stdout.write(table);
  final summary = results.option('summary');
  if (summary != null && summary.isNotEmpty) File(summary).writeAsStringSync(table, mode: .append);
  return 0;
}
