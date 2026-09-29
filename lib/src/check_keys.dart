/// Refuses a build whose keys file carries a key the repository does not allow.
///
/// Everything in the file is compiled into the binary by `--dart-define-from-file`; four apps still
/// carried an `AI_KEY` line on 2026-09-27. The allowlist is `dev_tool.keys` in `pubspec.yaml`, and
/// with none no key passes: a guard for secrets fails closed.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/config.dart';

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

/// `check_keys [--root <dir>] [--file <path>]`: exit 0 when the keys file holds only allowed keys.
int runCheckKeys(List<String> args) {
  final parser = commandParser()
    ..addOption('file', valueHelp: 'path', defaultsTo: 'config/keys.env', help: 'The keys file, relative to the root.');
  final results = parseArgs(parser, args, 'check_keys [--root <dir>] [--file <path>]');
  final root = rootOf(results);
  final name = results.option('file')!;
  final file = File(File(name).isAbsolute ? name : '$root/$name');
  if (!file.existsSync()) {
    final copy = File('${file.path}.example').existsSync() ? ' Copy $name.example to $name and fill it in.' : '';
    stderr.writeln('$name is missing.$copy It is gitignored; CI writes its own from the KEYS_ENV secret.');
    return 1;
  }
  final allowed = loadConfig(root).keys;
  final extra = disallowedKeys(file.readAsStringSync(), allowed);
  if (extra.isEmpty) return 0;
  stderr.writeln(
    '$name carries ${extra.join(', ')}, which dev_tool.keys in pubspec.yaml does not allow '
    '(allowed: ${allowed.isEmpty ? 'none' : allowed.join(', ')}). Everything in that file is compiled '
    'into the app: remove the key, or add it to dev_tool.keys if shipping it is intended.',
  );
  return 1;
}
