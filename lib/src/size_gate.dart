/// Reports a built bundle's size as a Markdown table and, when it has a budget, asserts it fits.
///
/// ```sh
/// dart run dev_tool:size_gate --file build/app/outputs/bundle/release/app-release.aab
/// dart run dev_tool:size_gate --file "$IPA" --summary "$GITHUB_STEP_SUMMARY" --label "1.0.0 (+3527000)"
/// dart run dev_tool:size_gate --file <path> --budget-mb 1        # prove the gate can fail
/// ```
///
/// The budget is `--budget-mb`, else `dev_tool.release.size_budget_mb` in `pubspec.yaml`, in MiB;
/// with neither the size is reported and not gated. Exit codes: 0 within budget or without one,
/// 1 over budget, 2 bad usage.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/config.dart';

/// `size_gate --file <path> [--budget-mb <n>] [--summary <file>] [--label <text>] [--row Name=Value]...`.
int runSizeGate(List<String> args) {
  final parser = commandParser()
    ..addOption('file', valueHelp: 'path', help: 'The bundle to measure (AAB, IPA, APK, ...).')
    ..addOption('budget-mb', valueHelp: 'MiB', help: 'The ceiling (default: dev_tool.release.size_budget_mb).')
    ..addOption('summary', valueHelp: 'file', help: r'Append the table to this file (CI: $GITHUB_STEP_SUMMARY).')
    ..addOption('label', valueHelp: 'text', help: 'The table heading.')
    ..addMultiOption('row', valueHelp: 'Name=Value', splitCommas: false, help: 'An extra table row; repeatable.');
  final results = parseArgs(
    parser,
    args,
    'size_gate --file <path> [--root <dir>] [--budget-mb <n>] [--summary <file>] [--label <text>] [--row Name=Value]...',
  );
  final path = results.option('file');
  if (path == null) throw const UsageException('--file is required: the bundle to measure');
  final bundle = File(path);
  if (!bundle.existsSync()) throw UsageException('bundle not found: $path');

  final rows = <String, String>{};
  for (final row in results.multiOption('row')) {
    final at = row.indexOf('=');
    if (at <= 0) throw UsageException('--row needs `Name=Value`, got "$row"');
    rows[row.substring(0, at)] = row.substring(at + 1);
  }

  final budgetText = results.option('budget-mb');
  final budgetMb = budgetText == null ? loadConfig(rootOf(results)).sizeBudgetMb : int.tryParse(budgetText);
  if (budgetText != null && (budgetMb == null || budgetMb <= 0)) {
    throw UsageException('--budget-mb needs a positive integer, got "$budgetText"');
  }

  final name = bundle.uri.pathSegments.last;
  final bytes = bundle.lengthSync();
  final table = StringBuffer()
    ..writeln('### ${results.option('label') ?? 'Bundle size'}')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---|')
    ..writeln('| File | `$name` |')
    ..writeln('| Size | `${iec(bytes)}` ($bytes bytes) |')
    ..writeln('| Budget | ${budgetMb == null ? 'none' : '`${budgetMb}MiB`'} |');
  for (final row in rows.entries) {
    table.writeln('| ${row.key} | ${row.value} |');
  }
  stdout.write(table);
  final summary = results.option('summary');
  if (summary != null && summary.isNotEmpty) File(summary).writeAsStringSync(table.toString(), mode: .append);

  if (budgetMb == null) {
    stdout.writeln('no budget (dev_tool.release.size_budget_mb): the size is reported, not gated');
    return 0;
  }
  if (bytes > budgetMb * 1024 * 1024) {
    stderr.writeln(
      '::error::$name is $bytes bytes (${iec(bytes)}), over the ${budgetMb}MiB budget. Find the dependency '
      'that grew before raising the ceiling.',
    );
    return 1;
  }
  stdout.writeln('within budget: ${iec(bytes)} <= ${budgetMb}MiB');
  return 0;
}

/// [bytes] in binary units with one decimal, e.g. `75.3MiB`.
String iec(int bytes) {
  const units = <String>['B', 'KiB', 'MiB', 'GiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)}${units[unit]}';
}
