/// The packages a pub workspace declares, read from the root `pubspec.yaml`: `dart pub workspace
/// list --json` took 22 s to answer what the YAML answers in a millisecond (2026-09-20).
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:yaml/yaml.dart';

/// The `workspace:` members of [pubspec] (the root pubspec under [root]) as directories relative to
/// [root], in declaration order. A glob entry (`packages/*`) expands, as pub expands it, to the
/// directories it matches that hold a `pubspec.yaml`, sorted.
List<String> workspaceMembers(String root, YamlMap pubspec) {
  final members = pubspec['workspace'];
  if (members == null) return const <String>[];
  if (members is! YamlList || members.any((member) => member is! String)) {
    throw const UsageException('pubspec.yaml: workspace must be a list of directories');
  }
  return <String>[
    for (final member in members.cast<String>())
      if (member.contains(RegExp('[*?[{]'))) ..._expand(root, member) else member.replaceFirst(RegExp(r'/+$'), ''),
  ];
}

List<String> _expand(String root, String pattern) {
  final base = root.replaceAll(r'\', '/');
  final prefix = base.endsWith('/') ? base : '$base/';
  return <String>[
    for (final entity in Glob(pattern).listSync(root: root))
      if (entity is Directory && File('${entity.path}/pubspec.yaml').existsSync())
        entity.path.replaceAll(r'\', '/').replaceFirst(prefix, ''),
  ]..sort();
}
