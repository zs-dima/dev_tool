import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/build_number.dart' show runBuildNumber;
import 'package:test/test.dart';

/// The build number must equal what the release workflows computed in shell before this existed:
/// `NUMBER=$(( _VC_BASE + ( $(date +%s) - _VC_T0 ) / 60 ))`. A different number on the same minute
/// would be a second rule, and two rules for one versionCode is how a store's floor gets burnt.
void main() {
  const now = 1790000000;

  test("a platform's own clock comes from dev_tool.release in the pubspec", () {
    // BreakerSonar's pair, from its release-android.yml: (1790000000 - 1788877826) / 60 = 18702.
    final config = parseConfig(<String, Object?>{
      'release': <String, Object?>{
        'android': <String, Object?>{'build_number_base': 1788806426, 'build_number_t0': 1788877826},
      },
    });
    expect(buildNumber(config.clock('android'), now), equals(1788806426 + 18702));
  });

  test('without a clock every platform counts minutes since 2020', () {
    for (final platform in <String>['android', 'ios', 'windows']) {
      expect(const DevToolConfig().clock(platform), equals(kDefaultClock), reason: platform);
    }
    expect(buildNumber(kDefaultClock, now), equals(3536053), reason: 'seven digits, as the iOS floor is');
  });

  test('one number per minute: the same minute gives the same number, the next gives one more', () {
    const minute = 1577836800 + 60 * 1000;
    expect(buildNumber(kDefaultClock, minute), equals(buildNumber(kDefaultClock, minute + 59)));
    expect(buildNumber(kDefaultClock, minute + 60), equals(buildNumber(kDefaultClock, minute) + 1));
  });

  test("a number above Play's ceiling is refused here, not at upload", () {
    expect(() => buildNumber((base: kPlayCeiling, t0: now), now + 60), throwsA(isA<UsageException>()));
  });

  test('a platform name that is not an identifier, or an unknown option, is refused', () {
    expect(() => runBuildNumber(<String>['Android']), throwsA(isA<UsageException>()));
    expect(
      () => runBuildNumber(<String>['android', '--at-seconds', '5']),
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains('at-seconds'))),
    );
    expect(() => runBuildNumber(<String>[]), throwsA(isA<UsageException>()));
  });

  group('the executable', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dev_tool_build_number');
      File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: app
dev_tool:
  release:
    android: {build_number_base: 1788806426, build_number_t0: 1788877826}
''');
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<ProcessResult> run(List<String> args) =>
        Process.run('dart', <String>['run', 'dev_tool:build_number', ...args], runInShell: Platform.isWindows);

    test('prints the number and nothing else', () async {
      final result = await run(<String>['android', '--root', root.path, '--at', '$now']);
      expect(result.exitCode, isZero, reason: result.stderr.toString());
      expect(result.stdout.toString().trim(), equals('1788825128'));
      expect(result.stdout.toString().trim().split('\n'), hasLength(1));
    });

    test('--help prints the usage and exits 0; a usage error exits 2', () async {
      final help = await run(<String>['--help']);
      expect(help.exitCode, isZero);
      expect(help.stdout.toString(), contains('usage: build_number <platform>'));
      final wrong = await run(<String>['--root', root.path]);
      expect(wrong.exitCode, equals(2));
      expect(wrong.stderr.toString(), contains('missing arguments'));
    });
  });
}
