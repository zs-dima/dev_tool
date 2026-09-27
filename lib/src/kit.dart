/// Points a repository's kit dependencies at local checkouts through `pubspec_overrides.yaml`
/// (gitignored): `kit link` while a package and its consumer change together, `kit unlink` before
/// committing. The set is derived from the pubspecs: the apps' hand-written map had fallen three
/// packages behind by 2026-09-27.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:yaml/yaml.dart';

/// The file this writes and removes.
const String kOverrides = 'pubspec_overrides.yaml';

/// One direct dependency a local checkout could replace: git dependencies by repository name and
/// sub-path, hosted ones by package name.
typedef KitDependency = ({String name, String repo, String subpath});

/// The replaceable direct dependencies of the repository at [root], sorted by name; path and SDK
/// dependencies are never linked.
List<KitDependency> kitDependencies(String root) {
  final found = <String, KitDependency>{};
  for (final pubspec in _pubspecs(root)) {
    for (final section in const <String>['dependencies', 'dev_dependencies']) {
      final deps = pubspec[section];
      if (deps is! YamlMap) continue;
      for (final MapEntry(:key, :value) in deps.entries) {
        final name = key as String;
        if (value is YamlMap) {
          if (value.containsKey('path') || value.containsKey('sdk')) continue;
          final git = value['git'];
          if (git != null) {
            final url = git is YamlMap ? git['url'] as String? : git as String;
            if (url == null) continue;
            final repo = url.replaceFirst(RegExp(r'\.git/?$'), '').split(RegExp('[/:]')).last;
            final subpath = git is YamlMap ? (git['path'] as String? ?? '') : '';
            found[name] = (name: name, repo: repo, subpath: subpath);
            continue;
          }
        }
        found.putIfAbsent(name, () => (name: name, repo: name, subpath: ''));
      }
    }
  }
  return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Which of [kits] (resolved directories) checks out [dependency], and its path below that
/// directory; the pubspec there must carry the dependency's name.
({int kit, String tail})? localCheckout(KitDependency dependency, List<String> kits) {
  final tail = [dependency.repo, if (dependency.subpath.isNotEmpty) dependency.subpath].join('/');
  for (var i = 0; i < kits.length; i++) {
    final pubspec = File('${kits[i]}/$tail/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final parsed = loadYaml(pubspec.readAsStringSync());
    if (parsed is YamlMap && parsed['name'] == dependency.name) return (kit: i, tail: tail);
  }
  return null;
}

/// The overrides file for [paths] (package name → directory).
String overridesYaml(Map<String, String> paths) {
  final buffer = StringBuffer()
    ..writeln('# Local only, gitignored. Written by `just kit-link`, removed by `just kit-unlink`.')
    ..writeln('dependency_overrides:');
  for (final name in paths.keys.toList()..sort()) {
    buffer
      ..writeln('  $name:')
      ..writeln('    path: ${paths[name]}');
  }
  return buffer.toString();
}

/// `kit link --kit <dir>[<path-separator><dir>...] [--kit <dir>]... [--root <repo>]`,
/// `kit unlink [--root <repo>]`. `--kit` is a list in the platform's PATH form (`;` on Windows, `:`
/// elsewhere) or repeated; a relative directory is taken from the repository root.
int runKit(List<String> args) {
  rejectUnknownOptions(args, const <String>{'root', 'kit'});
  final root = rootOf(args);
  final command = withoutOptions(args, const <String>{'root', 'kit'}).where((a) => !a.startsWith('--')).firstOrNull;
  final file = File('$root/$kOverrides');
  switch (command) {
    case 'unlink':
      if (file.existsSync()) file.deleteSync();
      stdout.writeln('$kOverrides removed; run `pub get` to resolve the pinned versions again.');
      return 0;

    case 'link':
      final kits = <String>[
        for (final value in options(args, 'kit'))
          ...value.split(Platform.isWindows ? ';' : ':').where((part) => part.trim().isNotEmpty),
      ];
      if (kits.isEmpty) {
        throw const UsageException('kit link needs --kit <dir>: the directory holding the kit checkouts (KIT in .env)');
      }
      final resolved = <String>[
        for (final kit in kits)
          if (File(kit).isAbsolute) kit else '$root/$kit',
      ];
      final linked = <String, String>{};
      for (final dependency in kitDependencies(root)) {
        final at = localCheckout(dependency, resolved);
        if (at != null) linked[dependency.name] = '${kits[at.kit]}/${at.tail}'.replaceAll(r'\', '/');
      }
      if (linked.isEmpty) {
        stderr.writeln('No dependency of this repository is checked out under ${kits.join(', ')}.');
        return 1;
      }
      // pub reads only this file once it exists: overrides committed in pubspec.yaml stop applying.
      final committed = yamlMap('$root/pubspec.yaml')?['dependency_overrides'];
      if (committed is YamlMap) {
        final hidden = committed.keys.cast<String>().where((name) => !linked.containsKey(name)).toList();
        if (hidden.isNotEmpty) {
          stderr.writeln(
            'pubspec.yaml carries dependency_overrides for ${hidden.join(', ')}; pub ignores them while $kOverrides exists.',
          );
        }
      }
      file.writeAsStringSync(overridesYaml(linked));
      stdout.writeln('$kOverrides -> ${linked.length} package(s): ${linked.keys.join(', ')}');
      return 0;

    default:
      throw const UsageException('usage: kit link --kit <dir> [--root <repo>] | kit unlink [--root <repo>]');
  }
}

/// The root pubspec and every workspace member's, parsed.
List<YamlMap> _pubspecs(String root) {
  final rootPubspec = yamlMap('$root/pubspec.yaml');
  if (rootPubspec == null) throw UsageException('no pubspec.yaml under $root');
  final members = rootPubspec['workspace'];
  return <YamlMap>[
    rootPubspec,
    if (members is YamlList)
      for (final member in members)
        if (yamlMap('$root/$member/pubspec.yaml') case final YamlMap pubspec) pubspec,
  ];
}
