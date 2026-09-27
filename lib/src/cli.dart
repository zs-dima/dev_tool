/// What every executable shares: usage errors, option parsing, the app's identity file.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// A command-line or input mistake. The executable prints [message] and exits with 2.
final class UsageException implements Exception {
  /// Creates the exception with the text shown to the user.
  const UsageException(this.message);

  /// What went wrong and, where it helps, how to fix it.
  final String message;

  @override
  String toString() => message;
}

/// The value of `--name value` or `--name=value` in [args], or `null` when absent.
String? option(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--$name') {
      if (i + 1 >= args.length) throw UsageException('--$name needs a value');
      return args[i + 1];
    }
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return null;
}

/// Every value of a repeatable `--name`, in order.
List<String> options(List<String> args, String name) => <String>[
  for (var i = 0; i < args.length; i++)
    if (args[i] == '--$name' && i + 1 < args.length)
      args[i + 1]
    else if (args[i].startsWith('--$name='))
      args[i].substring(name.length + 3),
];

/// [args] without the named options and their values, so the rest can be forwarded.
List<String> withoutOptions(List<String> args, Set<String> names) {
  final kept = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--') && names.contains(arg.substring(2))) {
      i++;
      continue;
    }
    if (names.any((name) => arg.startsWith('--$name='))) continue;
    kept.add(arg);
  }
  return kept;
}

/// Throws when [args] carries an option outside [known]: a typo must not pass as a default.
void rejectUnknownOptions(List<String> args, Set<String> known) {
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2).split('=').first;
    if (!known.contains(name)) throw UsageException('unknown option --$name');
  }
}

/// The repository root an executable works on: `--root`, else the current directory.
String rootOf(List<String> args) => option(args, 'root') ?? Directory.current.path;

/// The YAML map in the file at [path]; `null` when the file is missing or holds something else.
YamlMap? yamlMap(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final parsed = loadYaml(file.readAsStringSync());
  return parsed is YamlMap ? parsed : null;
}

/// Where every app keeps its identity: slug, products, size budget, release clock, key allowlist.
const String kAppJson = 'tool/newapp/app.json';

/// The app's `tool/newapp/app.json` under [root].
Map<String, Object?> readAppJson(String root) {
  final file = File('$root/$kAppJson');
  if (!file.existsSync()) {
    throw UsageException('$kAppJson not found under $root: run from the app root or pass --root');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) throw const UsageException('$kAppJson is not a JSON object');
  return decoded;
}

/// Runs [body] as an executable's `main`: a [UsageException] prints its message and exits 2; the
/// exit code of [body] is the process's.
Future<Never> runMain(FutureOr<int> Function() body) async {
  try {
    exit(await body());
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }
}
