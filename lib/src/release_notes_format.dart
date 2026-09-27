/// The pure half of `release_notes`: changelog text in, store card out.
library;

/// Play's "What's new" limit.
const int kStoreLimit = 500;

/// The body between one `## [version]` heading and the next `## ` heading; `null` [version] takes
/// the newest section with a body (an empty `## [Unreleased]` stays after a release). No section or
/// an empty one returns `null`.
String? section(String changelog, String? version) {
  final headings = RegExp(r'^## \[([^\]]+)\].*$', multiLine: true).allMatches(changelog).toList();
  if (headings.isEmpty) return null;

  String body(RegExpMatch heading) {
    final next = headings.where((candidate) => candidate.start > heading.start).firstOrNull;
    return changelog.substring(heading.end, next?.start ?? changelog.length).trim();
  }

  if (version != null) {
    final match = headings.where((heading) => heading.group(1) == version).firstOrNull;
    if (match == null) return null;
    final text = body(match);
    return text.isEmpty ? null : text;
  }

  for (final heading in headings) {
    final text = body(heading);
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// Play's "What's new" is 500 characters of plain text. Emphasis is stripped only in pairs: a lone
/// `_` turned `run_id` into `runid`.
String forStore(String source) => fit(
  source
      .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'(?<![\w`])_([^_`]+)_(?![\w`])'), (m) => m.group(1)!)
      .replaceAll('`', '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .replaceAll(RegExp('^#+ *', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim(),
);

/// [text] within [kStoreLimit] characters, cut on a line boundary so a note never ends mid-sentence.
String fit(String text) {
  if (text.length <= kStoreLimit) return text;

  final kept = StringBuffer();
  for (final line in text.split('\n')) {
    if (kept.length + line.length + 1 > kStoreLimit) break;
    if (kept.isNotEmpty) kept.write('\n');
    kept.write(line);
  }
  if (kept.isNotEmpty) return kept.toString();

  // One line over the limit is cut on a rune boundary within 500 UTF-16 units: a cut at 500 units
  // can split a surrogate pair, and 500 runes can be 1000 units.
  final runes = <int>[];
  var units = 0;
  for (final rune in text.runes) {
    final width = rune > 0xFFFF ? 2 : 1;
    if (units + width > kStoreLimit) break;
    runes.add(rune);
    units += width;
  }
  return String.fromCharCodes(runes);
}
