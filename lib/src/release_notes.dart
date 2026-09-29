/// The release notes of one version out of `CHANGELOG.md`, in two outputs:
///
/// * `<out>/release-notes/en-US.md`: the section verbatim, for `gh release create --notes-file`.
/// * `<out>/release-notes.json`: one entry per store locale within Play's 500 characters, for
///   `google-play bundles publish`.
///
/// `en-US` is the changelog section; another locale comes from `store/play/listing/<locale>/whatsnew.txt`
/// when one is written, else it is left out. With no version the newest section that has a body
/// wins; an explicit version with no section fails (the fallback once shipped a Play card reading
/// "Unreleased").
library;

import 'dart:convert';
import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/release_notes_format.dart';

/// The store entries for [body] under [root]: `en-US` from [body], then every other written locale.
List<Map<String, String>> storeEntries(String root, String body) {
  final entries = <Map<String, String>>[
    <String, String>{'language': 'en-US', 'text': forStore(body)},
  ];
  final listing = Directory('$root/store/play/listing');
  if (!listing.existsSync()) return entries;
  final locales =
      listing
          .listSync()
          .whereType<Directory>()
          .map((dir) => dir.uri.pathSegments.where((segment) => segment.isNotEmpty).last)
          .where((locale) => locale != 'en-US')
          .toList()
        ..sort();
  for (final locale in locales) {
    if (_whatsNew(root, locale) case final String text) entries.add(<String, String>{'language': locale, 'text': text});
  }
  return entries;
}

String? _whatsNew(String root, String locale) {
  final file = File('$root/store/play/listing/$locale/whatsnew.txt');
  if (!file.existsSync()) return null;
  final text = file.readAsStringSync().trim();
  return text.isEmpty ? null : fit(text);
}

/// `release_notes [version] [--root <dir>] [--out <dir>]`; `--out` defaults to `<root>/build`.
int runReleaseNotes(List<String> args) {
  final parser = commandParser()
    ..addOption('out', valueHelp: 'dir', help: 'Where the notes go (default: <root>/build).');
  final results = parseArgs(parser, args, 'release_notes [version] [--root <dir>] [--out <dir>]', maxRest: 1);
  final root = rootOf(results);
  final out = results.option('out') ?? '$root/build';
  final version = results.rest.isEmpty ? null : results.rest.single.replaceFirst(RegExp('^v'), '');

  final changelog = File('$root/CHANGELOG.md');
  if (!changelog.existsSync()) throw UsageException('CHANGELOG.md not found under $root');

  final body = section(changelog.readAsStringSync(), version);
  if (body == null) {
    stderr.writeln(
      version == null
          ? 'CHANGELOG.md has no `## [...]` section with anything under it.'
          : 'CHANGELOG.md has no `## [$version]` section with anything under it.\n'
                'Add one before tagging, or rename `## [Unreleased]` to `## [$version]`: a release with no '
                'notes shows testers a card that says "Unreleased", and an empty card is the same mistake.',
    );
    return 1;
  }

  final notesDir = Directory('$out/release-notes')..createSync(recursive: true);
  File('${notesDir.path}/en-US.md').writeAsStringSync(body);
  final entries = storeEntries(root, body);
  File('$out/release-notes.json').writeAsStringSync(jsonEncode(entries));

  stdout.writeln('Release notes for ${version ?? 'the newest section'}:');
  for (final entry in entries) {
    stdout.writeln('  ${entry['language']}: ${entry['text']!.length} chars');
  }
  return 0;
}
