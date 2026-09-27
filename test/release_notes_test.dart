import 'dart:convert';
import 'dart:io';

import 'package:dev_tool/src/release_notes.dart';
import 'package:test/test.dart';

/// The tool end to end on a throwaway repository: both outputs, the locale rules, and the loud
/// failure on a tag with no section. Everything is written under a temporary root, never into a
/// shared `build/` that other tests read.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dev_tool_release_notes');
    File('${root.path}/CHANGELOG.md').writeAsStringSync('''
# Changelog

## [Unreleased]

## [1.1.0] - 2026-09-20

### Added
- The **verdict** screen names the likely cause.
''');
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A directory Windows still holds a handle on is one stale temp folder, not a failed test.
    }
  });

  void whatsNew(String locale, String text) => File('${root.path}/store/play/listing/$locale/whatsnew.txt')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  List<Map<String, Object?>> entries(String out) =>
      (jsonDecode(File('$out/release-notes.json').readAsStringSync()) as List<Object?>).cast<Map<String, Object?>>();

  test('writes both outputs under <root>/build by default', () {
    expect(runReleaseNotes(<String>['1.1.0', '--root', root.path]), isZero);
    expect(File('${root.path}/build/release-notes/en-US.md').readAsStringSync(), contains('**verdict**'));
    expect(
      entries('${root.path}/build').single,
      equals(<String, Object?>{
        'language': 'en-US',
        'text': 'Added\n- The verdict screen names the likely cause.',
      }),
    );
  });

  test('--out moves both outputs', () {
    final out = '${root.path}/elsewhere';
    expect(runReleaseNotes(<String>['v1.1.0', '--root', root.path, '--out', out]), isZero);
    expect(File('$out/release-notes/en-US.md').existsSync(), isTrue);
    expect(Directory('${root.path}/build').existsSync(), isFalse);
  });

  test('another locale comes from its written whatsnew; en-US is always the changelog section', () {
    whatsNew('ru-RU', 'Экран вердикта.');
    Directory('${root.path}/store/play/listing/es-ES').createSync(recursive: true); // no whatsnew
    whatsNew('en-US', 'First public release.'); // a launch card left behind must not ship again
    expect(runReleaseNotes(<String>['--root', root.path]), isZero);
    final written = entries('${root.path}/build');
    expect(
      written.map((e) => e['language']),
      equals(<String>['en-US', 'ru-RU']),
      reason: 'a locale with no written card is left out: a card in the wrong language is worse than none',
    );
    expect(written.first['text'], contains('verdict'));
    expect(written.first['text'], isNot(contains('First public release')));
  });

  test('a tag with no changelog section fails the release instead of shipping "Unreleased"', () {
    expect(runReleaseNotes(<String>['v999.0.0', '--root', root.path]), equals(1));
    expect(File('${root.path}/build/release-notes.json').existsSync(), isFalse);
  });
}
