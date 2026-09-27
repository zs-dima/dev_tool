/// Asserts a built app bundle fits the app's size budget (`sizeBudgetMb` in `tool/newapp/app.json`)
/// and writes the numbers to a step summary.
///
/// ```sh
/// dart run dev_tool:size_gate --aab build/app/outputs/bundle/release/app-release.aab
/// dart run dev_tool:size_gate --ipa build/ios/ipa/app.ipa --summary "$GITHUB_STEP_SUMMARY" --label "1.0.0 (+3527000)"
/// dart run dev_tool:size_gate --aab <path> --budget-mb 1        # prove the gate can fail
/// ```
///
/// Exit codes: 0 within budget, 1 over budget, 2 bad usage.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';

/// Runs the gate; `--root` names the app (default: cwd).
int runSizeGate(List<String> args) {
  final aab = option(args, 'aab');
  final ipa = option(args, 'ipa');
  final summary = option(args, 'summary');
  final label = option(args, 'label');
  final budgetText = option(args, 'budget-mb');
  final rows = <String, String>{};
  for (final row in options(args, 'row')) {
    final at = row.indexOf('=');
    if (at <= 0) throw UsageException('--row needs `Name=Value`, got "$row"');
    rows[row.substring(0, at)] = row.substring(at + 1);
  }
  final known = <String>{'aab', 'ipa', 'summary', 'label', 'budget-mb', 'row', 'root'};
  final unknown = withoutOptions(args, known);
  if (unknown.isNotEmpty) {
    throw UsageException(
      'unknown argument: ${unknown.first}\n'
      'usage: size_gate (--aab <path> | --ipa <path>) [--root <dir>] [--summary <file>] [--label <text>] '
      '[--budget-mb <n>] [--row Name=Value]',
    );
  }

  if ((aab == null) == (ipa == null)) throw const UsageException('exactly one of --aab or --ipa is required');
  final path = aab ?? ipa!;
  final bundle = File(path);
  if (!bundle.existsSync()) throw UsageException('bundle not found: $path');

  final budgetMb = budgetText == null ? _budgetFromSpec(rootOf(args)) : int.tryParse(budgetText);
  if (budgetMb == null) throw const UsageException('--budget-mb needs an integer');

  final bytes = bundle.lengthSync();
  final table = StringBuffer()
    ..writeln('### ${label ?? 'App bundle size'}')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---|')
    ..writeln('| ${aab != null ? 'AAB' : 'IPA'} file (upload) | `${iec(bytes)}` ($bytes bytes) |')
    ..writeln('| Budget | `$budgetMb MB` |');
  for (final row in rows.entries) {
    table.writeln('| ${row.key} | ${row.value} |');
  }

  stdout.write(table);
  if (summary != null && summary.isNotEmpty) File(summary).writeAsStringSync(table.toString(), mode: .append);

  if (bytes > budgetMb * 1024 * 1024) {
    stderr.writeln(
      '::error::App bundle is $bytes bytes (${iec(bytes)}), over the $budgetMb MB budget ($kAppJson '
      '`sizeBudgetMb`). Find the dependency that grew before raising the ceiling.',
    );
    return 1;
  }
  stdout.writeln('within budget: ${iec(bytes)} <= $budgetMb MB');
  return 0;
}

int _budgetFromSpec(String root) {
  final budget = readAppJson(root)['sizeBudgetMb'];
  if (budget is! int) throw const UsageException('$kAppJson has no integer `sizeBudgetMb`');
  return budget;
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
