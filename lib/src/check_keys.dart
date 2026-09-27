/// Refuses a build whose `config/keys.env` carries a key the app does not allow.
///
/// Everything in `keys.env` is compiled into the binary by `--dart-define-from-file`; four apps still
/// carried an `AI_KEY` line on 2026-09-27. The allowlist is `keys` in `tool/newapp/app.json`,
/// `["SENTRY_DSN"]` when absent.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';

/// The keys an app may compile in when its `app.json` names none.
const List<String> kDefaultKeys = <String>['SENTRY_DSN'];

/// The keys defined in [envFile] that [allowed] does not name, in file order.
List<String> disallowedKeys(String envFile, List<String> allowed) {
  final keys = <String>[];
  for (final raw in envFile.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
    final key = line.substring(0, line.indexOf('=')).replaceFirst(RegExp(r'^export\s+'), '').trim();
    if (!allowed.contains(key)) keys.add(key);
  }
  return keys;
}

/// The allowlist from the app's identity file.
List<String> allowedKeys(Map<String, Object?> app) {
  final keys = app['keys'];
  if (keys == null) return kDefaultKeys;
  if (keys is! List<Object?> || keys.any((key) => key is! String)) {
    throw const UsageException('$kAppJson: `keys` must be a list of environment variable names');
  }
  return keys.cast<String>();
}

/// `check_keys [--root <dir>]`: exit 0 when `config/keys.env` holds only allowed keys.
int runCheckKeys(List<String> args) {
  rejectUnknownOptions(args, const <String>{'root'});
  final root = rootOf(args);
  final file = File('$root/config/keys.env');
  if (!file.existsSync()) {
    stderr.writeln(
      'config/keys.env is missing. Copy config/keys.env.example to config/keys.env and fill it in '
      '(it is gitignored; CI writes its own from secrets).',
    );
    return 1;
  }
  final allowed = allowedKeys(readAppJson(root));
  final extra = disallowedKeys(file.readAsStringSync(), allowed);
  if (extra.isEmpty) return 0;
  stderr.writeln(
    'config/keys.env carries ${extra.join(', ')}, which $kAppJson `keys` does not allow '
    '(allowed: ${allowed.join(', ')}). Everything in that file is compiled into the app: remove the '
    'key, or add it to `keys` if shipping it is intended.',
  );
  return 1;
}
