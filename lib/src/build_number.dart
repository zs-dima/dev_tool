/// The build number of a release: minutes on a fixed clock, one rule for the recipe and the workflow.
///
/// Minutes, not seconds: Play caps `versionCode` at 2 100 000 000, which unixtime reaches on
/// 2036-07-18.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';

/// The line's base clock: 2020-01-01T00:00:00Z. iOS counts minutes from it with no offset.
const int kLineEpoch = 1577836800;

/// Play's upper bound for `versionCode`.
const int kPlayCeiling = 2100000000;

/// A release clock: the number at [t0] is [base], and it grows by one per minute.
typedef ReleaseClock = ({int base, int t0});

/// The clock for [platform] (`android` or `ios`): `release.<platform>.versionCodeBase` and
/// `versionCodeT0` in the app's `app.json` (an app whose store history holds numbers above the line
/// clock), else the line clock.
ReleaseClock releaseClock(Map<String, Object?> app, String platform) {
  if (platform != 'android' && platform != 'ios') {
    throw UsageException('platform must be android or ios, got "$platform"');
  }
  final release = app['release'];
  if (release == null) return (base: 0, t0: kLineEpoch);
  if (release is! Map<String, Object?>) throw const UsageException('$kAppJson: `release` must be an object');
  final entry = release[platform];
  if (entry == null) return (base: 0, t0: kLineEpoch);
  if (entry is! Map<String, Object?>) throw UsageException('$kAppJson: release.$platform must be an object');
  final base = entry['versionCodeBase'];
  final t0 = entry['versionCodeT0'];
  if (base is! int || t0 is! int) {
    throw UsageException('$kAppJson: release.$platform needs integer versionCodeBase and versionCodeT0');
  }
  return (base: base, t0: t0);
}

/// The build number at [nowSeconds] (unixtime) on [clock]. Two releases in one minute repeat a
/// number and the store rejects the second; a number past Play's ceiling is refused here.
int buildNumber(ReleaseClock clock, int nowSeconds) {
  final number = clock.base + (nowSeconds - clock.t0) ~/ 60;
  if (number <= 0) throw UsageException('build number $number is not positive: check versionCodeT0');
  if (number > kPlayCeiling) throw UsageException('build number $number is above Play\'s ceiling $kPlayCeiling');
  return number;
}

/// `build_number android|ios [--root <dir>] [--at <unix seconds>]`: prints the number and nothing else.
int runBuildNumber(List<String> args) {
  rejectUnknownOptions(args, const <String>{'root', 'at'});
  final positional = withoutOptions(args, const <String>{'root', 'at'}).where((a) => !a.startsWith('--')).toList();
  if (positional.length != 1) {
    throw const UsageException('usage: build_number android|ios [--root <dir>] [--at <unix seconds>]');
  }
  final at = option(args, 'at');
  final now = at == null ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : int.tryParse(at);
  if (now == null) throw UsageException('--at needs unix seconds, got "$at"');
  stdout.writeln(buildNumber(releaseClock(readAppJson(rootOf(args)), positional.single), now));
  return 0;
}
