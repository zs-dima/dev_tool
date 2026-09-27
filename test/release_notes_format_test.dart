import 'package:dev_tool/dev_tool.dart';
import 'package:test/test.dart';

/// The store card's formatting, driven by a FIXTURE: asserted against a live changelog, "an
/// identifier keeps its underscores" could not fail while that changelog held no such identifier.
void main() {
  const changelog = '''
# Changelog

## [Unreleased]

### Changed
- The journal keeps the `run_id` of every launch, and _emphasis_ is stripped.
- __dunder__ names and _leading underscores survive the card.
- A link to [the docs](https://example.invalid/docs) reads as its text.

## [1.2.0] - 2026-08-01

### Fixed
- Something older, which must not appear in the newest section.
''';

  group('section', () {
    test('takes the newest one when no version is named', () {
      final body = section(changelog, null)!;
      expect(body, contains('run_id'));
      expect(body, isNot(contains('Something older')), reason: 'one section, not the whole changelog');
    });

    test('takes the one named, not the newest', () {
      expect(section(changelog, '1.2.0'), contains('Something older'));
    });

    test('a version with no section is null, so the caller can fail the release', () {
      expect(section(changelog, '999.0.0'), isNull);
    });

    // The day after a release the newest heading is routinely empty (Keep a Changelog); taking it
    // literally wrote a zero-byte en-US.md on 2026-09-08.
    const justTagged = '''
# Changelog

## [Unreleased]

## [0.1.0] - 2026-09-08

### Added
- The first build.
''';

    test('an empty newest section is skipped, not returned as nothing', () {
      expect(section(justTagged, null), contains('The first build'));
    });

    test('an empty section asked for by name is null', () {
      expect(section(justTagged, 'Unreleased'), isNull);
    });
  });

  group('forStore', () {
    late String card;

    setUp(() => card = forStore(section(changelog, null)!));

    test('keeps the underscores of an identifier', () {
      expect(card, contains('run_id'), reason: 'a lone `_` used to be stripped: run_id became runid');
      expect(card, isNot(contains('runid')));
    });

    test('strips paired emphasis', () {
      expect(card, contains('emphasis is stripped'));
      expect(card, isNot(contains('_emphasis_')));
    });

    test('a doubled underscore is an identifier, not a marker', () {
      expect(card, contains('__dunder__'));
      expect(card, contains('_leading underscores survive'));
    });

    test('a link becomes its text', () {
      expect(card, contains('the docs'));
      expect(card, isNot(contains('https://')));
    });

    test('markdown headings and backticks are gone', () {
      expect(card, isNot(contains('###')));
      expect(card, isNot(contains('`')));
    });
  });

  group('fit', () {
    test('a short text is untouched', () {
      expect(fit('one line'), equals('one line'));
    });

    test('cuts on a line boundary rather than mid-sentence', () {
      final text = '${'a' * 400}\n${'b' * 400}';
      expect(fit(text), equals('a' * 400));
    });

    test('a single over-long line is cut on a RUNE boundary, inside the limit', () {
      // Each emoji is TWO UTF-16 units: 260 of them is 520 units but only 260 runes.
      final cut = fit('🔌' * 260);
      expect(cut.length, lessThanOrEqualTo(kStoreLimit), reason: 'Play counts UTF-16 units');
      expect(cut.runes.length, equals(kStoreLimit ~/ 2));
      expect(
        cut.codeUnits.where((unit) => unit >= 0xD800 && unit <= 0xDBFF).length,
        equals(cut.codeUnits.where((unit) => unit >= 0xDC00 && unit <= 0xDFFF).length),
        reason: 'a lone surrogate is invalid UTF-8 and Play rejects the card',
      );
    });
  });
}
