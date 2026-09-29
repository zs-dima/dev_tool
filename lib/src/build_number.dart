/// The build number of a release: minutes on a fixed clock, one rule for the recipe and the workflow.
///
/// Minutes, not seconds: Play caps `versionCode` at 2 100 000 000, which unixtime reaches on
/// 2036-07-18. Each platform's clock is `dev_tool.release.<platform>` in `pubspec.yaml` (a store
/// whose history already holds higher numbers continues from them), else [kDefaultClock].
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/config.dart';

/// Play's upper bound for `versionCode`; no store takes a number above it for a new build either.
const int kPlayCeiling = 2100000000;

/// The build number at [nowSeconds] (unixtime) on [clock]. Two releases in one minute repeat a
/// number and the store rejects the second; a number past [kPlayCeiling] is refused here.
int buildNumber(ReleaseClock clock, int nowSeconds) {
  final number = clock.base + (nowSeconds - clock.t0) ~/ 60;
  if (number <= 0) throw UsageException('build number $number is not positive: check build_number_t0');
  if (number > kPlayCeiling) throw UsageException("build number $number is above Play's ceiling $kPlayCeiling");
  return number;
}

/// `build_number <platform> [--root <dir>] [--at <unix seconds>]`: prints the number and nothing else.
int runBuildNumber(List<String> args) {
  final parser = commandParser()
    ..addOption('at', valueHelp: 'unix seconds', help: 'The moment to number (default: now).');
  final results = parseArgs(
    parser,
    args,
    'build_number <platform> [--root <dir>] [--at <unix seconds>]',
    minRest: 1,
    maxRest: 1,
  );
  final platform = results.rest.single;
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(platform)) {
    throw UsageException('platform must be a lower-case name such as android or ios, got "$platform"');
  }
  final at = results.option('at');
  final now = at == null ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : int.tryParse(at);
  if (now == null) throw UsageException('--at needs unix seconds, got "$at"');
  stdout.writeln(buildNumber(loadConfig(rootOf(results)).clock(platform), now));
  return 0;
}
