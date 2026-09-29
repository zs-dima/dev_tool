import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/check_keys.dart' show runCheckKeys;
import 'package:test/test.dart';

/// Everything in the keys file is compiled into the app: the check is the only thing between an API
/// key on a developer's disk and every bundle built from that disk.
void main() {
  test('only the allowlisted keys pass; comments, blanks, CRLF and `export` prefixes are understood', () {
    const env = '# the app keys\r\nSENTRY_DSN=https://example.invalid/1\r\n\r\nexport AI_KEY=sk-live\r\nOPENAI=x\r\n';
    expect(disallowedKeys(env, const <String>['SENTRY_DSN']), equals(<String>['AI_KEY', 'OPENAI']));
    expect(disallowedKeys('SENTRY_DSN=x\n', const <String>['SENTRY_DSN']), isEmpty);
  });

  group('the executable', () {
    late Directory root;

    void write(String path, String text) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    setUp(() => root = Directory.systemTemp.createTempSync('dev_tool_keys'));
    tearDown(() => root.deleteSync(recursive: true));

    test('with no allowlist nothing passes: the guard fails closed', () {
      write('pubspec.yaml', 'name: app\n');
      write('config/keys.env', 'SENTRY_DSN=x\n');
      expect(runCheckKeys(<String>['--root', root.path]), equals(1));
    });

    test('the allowlist is dev_tool.keys; a foreign key fails', () {
      write('pubspec.yaml', 'name: app\ndev_tool:\n  keys: [SENTRY_DSN]\n');
      write('config/keys.env', 'SENTRY_DSN=x\n');
      expect(runCheckKeys(<String>['--root', root.path]), isZero);
      write('config/keys.env', 'SENTRY_DSN=x\nAI_KEY=y\n');
      expect(runCheckKeys(<String>['--root', root.path]), equals(1));
    });

    test('--file names another keys file; a missing one fails with the fix', () {
      write('pubspec.yaml', 'name: app\ndev_tool:\n  keys: [MAPS_KEY]\n');
      write('secrets/web.env', 'MAPS_KEY=x\n');
      expect(runCheckKeys(<String>['--root', root.path, '--file', 'secrets/web.env']), isZero);
      expect(runCheckKeys(<String>['--root', root.path]), equals(1), reason: 'config/keys.env is missing');
    });
  });
}
