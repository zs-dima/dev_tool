/// What every executable shares: usage errors, `--help`, argument parsing, YAML reading.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

/// A command-line or input mistake. The executable prints [message] on stderr and exits with 2.
final class UsageException implements Exception {
  /// Creates the exception with the text shown to the user.
  const UsageException(this.message);

  /// What went wrong and, where it helps, how to fix it.
  final String message;

  @override
  String toString() => message;
}

/// `--help` was given: the executable prints [text] on stdout and exits with 0.
final class HelpRequested implements Exception {
  /// Creates the request with the usage text to print.
  const HelpRequested(this.text);

  /// The synopsis and the options.
  final String text;

  @override
  String toString() => text;
}

/// A parser with the options every executable takes: `--root` and `--help`.
ArgParser commandParser() => ArgParser()
  ..addOption('root', valueHelp: 'dir', defaultsTo: '.', help: 'The repository root.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage information.');

/// [args] parsed by [parser], with between [minRest] and [maxRest] positional arguments (`null`: any
/// number). A malformed command line is a [UsageException] carrying [synopsis] and the options;
/// `--help` is a [HelpRequested] with the same text.
ArgResults parseArgs(ArgParser parser, List<String> args, String synopsis, {int minRest = 0, int? maxRest = 0}) {
  final usage = 'usage: $synopsis\n\n${parser.usage}';
  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    throw UsageException('${e.message}\n\n$usage');
  }
  if (results.flag('help')) throw HelpRequested(usage);
  final rest = results.rest;
  if (rest.length < minRest || (maxRest != null && rest.length > maxRest)) {
    throw UsageException(
      '${rest.length < minRest ? 'missing arguments' : 'unexpected arguments: ${rest.join(' ')}'}\n\n$usage',
    );
  }
  return results;
}

/// The `--root` directory, absolute and with forward slashes: child processes run in other
/// directories, and a path built from it must mean the same file there.
String rootOf(ArgResults results) {
  final dir = Directory(results.option('root') ?? '.');
  if (!dir.existsSync()) throw UsageException('--root ${dir.path}: no such directory');
  return dir.resolveSymbolicLinksSync().replaceAll(r'\', '/');
}

/// The YAML map in the file at [path]; `null` when the file is missing or holds something else. A
/// file that is not YAML is a [UsageException] naming it, not a stack trace.
YamlMap? yamlMap(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final Object? parsed;
  try {
    parsed = loadYaml(file.readAsStringSync());
  } on YamlException catch (e) {
    throw UsageException('$path: ${e.message}');
  }
  return parsed is YamlMap ? parsed : null;
}

/// Runs [body] as an executable's `main`: its result is the exit code; a [UsageException] prints its
/// message and exits with 2; [HelpRequested] prints the usage and exits with 0. The process ends when
/// `main` returns, after stdout and stderr are flushed.
Future<void> runMain(FutureOr<int> Function() body) async {
  try {
    exitCode = await body();
  } on HelpRequested catch (e) {
    stdout.writeln(e.text);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
  }
}
