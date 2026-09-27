import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/check_keys.dart' show runCheckKeys;
import 'package:test/test.dart';

/// Everything in `config/keys.env` is compiled into the app: the check is the only thing between an
/// API key on a developer's disk and every bundle built from that disk.
void main() {
  test('only the allowlisted keys pass; comments, blanks and `export` prefixes are understood', () {
    const env = '''
# the app's keys
SENTRY_DSN=https://example.invalid/1

export AI_KEY=sk-live
OPENAI=x
''';
    expect(disallowedKeys(env, kDefaultKeys), equals(<String>['AI_KEY', 'OPENAI']));
    expect(disallowedKeys('SENTRY_DSN=x\n', kDefaultKeys), isEmpty);
  });

  test('the allowlist comes from app.json `keys`, SENTRY_DSN when absent', () {
    expect(allowedKeys(const <String, Object?>{}), equals(<String>['SENTRY_DSN']));
    expect(
      allowedKeys(<String, Object?>{
        'keys': <Object?>['SENTRY_DSN', 'MAPS_KEY'],
      }),
      equals(<String>['SENTRY_DSN', 'MAPS_KEY']),
    );
    expect(
      () => allowedKeys(<String, Object?>{
        'keys': <Object?>[1],
      }),
      throwsA(isA<UsageException>()),
    );
  });

  group('the executable', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dev_tool_keys');
      File('${root.path}/tool/newapp/app.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"slug": "demo"}');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a missing keys.env fails with the fix, not with flutter\'s file-not-found', () {
      expect(runCheckKeys(<String>['--root', root.path]), equals(1));
    });

    test('an allowed file passes and a foreign key fails', () {
      final env = File('${root.path}/config/keys.env')
        ..createSync(recursive: true)
        ..writeAsStringSync('SENTRY_DSN=x\n');
      expect(runCheckKeys(<String>['--root', root.path]), isZero);
      env.writeAsStringSync('SENTRY_DSN=x\nAI_KEY=y\n');
      expect(runCheckKeys(<String>['--root', root.path]), equals(1));
    });
  });
}
