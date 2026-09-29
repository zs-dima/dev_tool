/// Points a repository's kit dependencies at local checkouts through `pubspec_overrides.yaml`
/// (gitignored): `kit link` while a package and its consumer change together, `kit unlink` before
/// committing. The set is derived from the pubspecs: the apps' hand-written map had fallen three
/// packages behind by 2026-09-27.
///
/// The root's file covers the root and its workspace members; each standalone Dart package among
/// `dev_tool.test.extra` gets its own, because pub resolves it on its own and the test runner tests it.
library;

import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/config.dart';
import 'package:dev_tool/src/workspace.dart';
import 'package:yaml/yaml.dart';

/// The file this writes and removes.
const String kOverrides = 'pubspec_overrides.yaml';

/// One direct dependency a local checkout could replace: git dependencies by repository name and
/// sub-path, hosted ones by package name.
typedef KitDependency = ({String name, String repo, String subpath});

/// The replaceable direct dependencies in [pubspecs], sorted by name; path and SDK dependencies are
/// never linked.
List<KitDependency> kitDependencies(Iterable<YamlMap> pubspecs) {
  final found = <String, KitDependency>{};
  for (final pubspec in pubspecs) {
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

/// A directory that gets its own overrides file: [dir] relative to the root (`.` for the root), and
/// the pubspecs whose dependencies it resolves.
typedef _Target = ({String dir, List<YamlMap> pubspecs});

List<_Target> _targets(String root) {
  final pubspec = yamlMap('$root/pubspec.yaml');
  if (pubspec == null) throw UsageException('no readable pubspec.yaml under $root');
  return <_Target>[
    (
      dir: '.',
      pubspecs: <YamlMap>[
        pubspec,
        for (final member in workspaceMembers(root, pubspec))
          if (yamlMap('$root/$member/pubspec.yaml') case final YamlMap memberPubspec) memberPubspec,
      ],
    ),
    for (final dir in parseConfig(pubspec['dev_tool']).extras)
      if (yamlMap('$root/$dir/pubspec.yaml') case final YamlMap extraPubspec)
        (dir: dir, pubspecs: <YamlMap>[extraPubspec]),
  ];
}

const String _synopsis = 'kit link --kit <dir>[<path-separator><dir>...] [--kit <dir>]... [--root <dir>] | kit unlink';

/// `kit link --kit <dir>... [--root <repo>]`, `kit unlink [--root <repo>]`. `--kit` is a list in the
/// platform's PATH form (`;` on Windows, `:` elsewhere) or repeated; a relative directory is taken
/// from the repository root and written as given, rebased for an extra's own file.
int runKit(List<String> args) {
  final parser = commandParser()
    ..addMultiOption(
      'kit',
      valueHelp: 'dir',
      splitCommas: false,
      help: 'A directory holding kit checkouts (KIT in .env); a PATH-style list or repeated.',
    );
  final results = parseArgs(parser, args, _synopsis, minRest: 1, maxRest: 1);
  final root = rootOf(results);
  final targets = _targets(root);
  switch (results.rest.single) {
    case 'unlink':
      for (final target in targets) {
        final file = File('$root/${target.dir}/$kOverrides');
        if (file.existsSync()) file.deleteSync();
      }
      stdout.writeln('$kOverrides removed; run `pub get` to resolve the pinned versions again.');
      return 0;

    case 'link':
      final kits = <String>[
        for (final value in results.multiOption('kit'))
          ...value.split(Platform.isWindows ? ';' : ':').where((part) => part.trim().isNotEmpty),
      ];
      if (kits.isEmpty) {
        throw const UsageException('kit link needs --kit <dir>: the directory holding the kit checkouts (KIT in .env)');
      }
      final resolved = <String>[
        for (final kit in kits)
          if (File(kit).isAbsolute) kit else '$root/$kit',
      ];
      var linkedAny = false;
      for (final target in targets) {
        final depth = target.dir == '.' ? 0 : target.dir.split('/').length;
        final linked = <String, String>{};
        for (final dependency in kitDependencies(target.pubspecs)) {
          final at = localCheckout(dependency, resolved);
          if (at == null) continue;
          final kit = kits[at.kit];
          linked[dependency.name] = '${File(kit).isAbsolute ? kit : '${'../' * depth}$kit'}/${at.tail}'.replaceAll(
            r'\',
            '/',
          );
        }
        if (linked.isEmpty) continue;
        linkedAny = true;
        _warnHiddenOverrides(target, linked);
        final name = target.dir == '.' ? kOverrides : '${target.dir}/$kOverrides';
        File('$root/$name').writeAsStringSync(overridesYaml(linked));
        stdout.writeln('$name -> ${linked.length} package(s): ${linked.keys.join(', ')}');
      }
      if (!linkedAny) {
        stderr.writeln('No dependency of this repository is checked out under ${kits.join(', ')}.');
        return 1;
      }
      return 0;

    default:
      throw UsageException('unknown command "${results.rest.single}"\n\nusage: $_synopsis');
  }
}

/// pub reads only the overrides file once it exists: overrides committed in the pubspec stop applying.
void _warnHiddenOverrides(_Target target, Map<String, String> linked) {
  final committed = target.pubspecs.first['dependency_overrides'];
  if (committed is! YamlMap) return;
  final hidden = committed.keys.cast<String>().where((name) => !linked.containsKey(name)).toList();
  if (hidden.isEmpty) return;
  final where = target.dir == '.' ? 'pubspec.yaml' : '${target.dir}/pubspec.yaml';
  stderr.writeln(
    '$where carries dependency_overrides for ${hidden.join(', ')}; pub ignores them while $kOverrides exists.',
  );
}
