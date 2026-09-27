import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/build_number.dart' show runBuildNumber;
import 'package:test/test.dart';

/// The build number must equal what the release workflows computed in shell before this existed:
/// `NUMBER=$(( _VC_BASE + ( $(date +%s) - _VC_T0 ) / 60 ))`. A different number on the same minute
/// would be a second rule, and two rules for one versionCode is how a store's floor gets burnt.
void main() {
  const now = 1790000000;

  test('Android uses the app\'s own clock from app.json', () {
    // BreakerSonar's pair, from its release-android.yml: (1790000000 - 1788877826) / 60 = 18702.
    final clock = releaseClock(<String, Object?>{
      'release': <String, Object?>{
        'android': <String, Object?>{'versionCodeBase': 1788806426, 'versionCodeT0': 1788877826},
      },
    }, 'android');
    expect(buildNumber(clock, now), equals(1788806426 + 18702));
  });

  test('without a release block both platforms use the line clock: minutes since 2020', () {
    for (final platform in <String>['android', 'ios']) {
      final clock = releaseClock(const <String, Object?>{}, platform);
      expect(clock, equals((base: 0, t0: kLineEpoch)));
      expect(buildNumber(clock, now), equals((now - kLineEpoch) ~/ 60), reason: platform);
    }
    expect(buildNumber((base: 0, t0: kLineEpoch), now), equals(3536053), reason: 'seven digits, as the iOS floor is');
  });

  test('one number per minute: the same minute gives the same number, the next gives one more', () {
    const clock = (base: 0, t0: kLineEpoch);
    const minute = kLineEpoch + 60 * 1000;
    expect(buildNumber(clock, minute), equals(buildNumber(clock, minute + 59)));
    expect(buildNumber(clock, minute + 60), equals(buildNumber(clock, minute) + 1));
  });

  test('a number above Play\'s ceiling is refused here, not at upload', () {
    expect(() => buildNumber((base: kPlayCeiling, t0: kLineEpoch), kLineEpoch + 60), throwsA(isA<UsageException>()));
  });

  test('a half-written release block is an error, not the line clock', () {
    expect(
      () => releaseClock(<String, Object?>{
        'release': <String, Object?>{
          'android': <String, Object?>{'versionCodeBase': 1},
        },
      }, 'android'),
      throwsA(isA<UsageException>()),
    );
    expect(() => releaseClock(const <String, Object?>{}, 'web'), throwsA(isA<UsageException>()));
  });

  test('a release block that is not an object is refused, not read as the line clock', () {
    expect(
      () => releaseClock(<String, Object?>{
        'release': <String, Object?>{
          'android': <int>[1788816828, 1788869018],
        },
      }, 'android'),
      throwsA(isA<UsageException>()),
    );
    expect(() => releaseClock(<String, Object?>{'release': 'later'}, 'ios'), throwsA(isA<UsageException>()));
  });

  test('an unknown option is refused, not ignored', () {
    expect(
      () => runBuildNumber(<String>['android', '--at-seconds', '5']),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('--at-seconds'))),
    );
  });

  test('the executable prints the number and nothing else', () async {
    final root = Directory.systemTemp.createTempSync('dev_tool_build_number');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/tool/newapp/app.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"release": {"android": {"versionCodeBase": 1788806426, "versionCodeT0": 1788877826}}}');
    final run = await Process.run('dart', <String>[
      'run',
      'dev_tool:build_number',
      'android',
      '--root',
      root.path,
      '--at',
      '$now',
    ], runInShell: Platform.isWindows);
    expect(run.exitCode, isZero, reason: run.stderr.toString());
    expect(run.stdout.toString().trim(), equals('1788825128'));
    expect(run.stdout.toString().trim().split('\n'), hasLength(1));
  });
}
