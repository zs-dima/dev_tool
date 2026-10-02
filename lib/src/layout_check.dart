/// The structural layout check: two laws a widget test cannot see, and the perf mistakes no lint can
/// express, as a regex scan a repository runs from its own suite.
///
/// ```dart
/// test('the layout laws hold', () => expect(scanProject(), isEmpty));
/// ```
///
/// The laws: a scrollable is never wrapped in a box (its insets go inside it), and a subtree never
/// changes shape on a runtime condition. Both were broken across a shipped app with every test
/// green: tests run with no system padding and never resize a window.
///
/// **What this is not.** It does not repeat DCM: `avoid-shrink-wrap-in-lists`,
/// `avoid-returning-widgets`, `prefer-dedicated-media-query-methods`, `prefer-const-*` and
/// `avoid-wrapping-in-padding` exist there. Here is what a rule engine over one expression cannot
/// see: a scrollable behind a wrapper of the repository's own, a subtree that changes shape between
/// two builds, a getter that mints a new stream each time it is read.
///
/// Regex over source, deliberately. An analyzer plugin would be more precise and would not run where
/// this has to: as one test of a suite, on any machine, with no package resolution and no licence.
/// The cost is false positives, so every rule is silenced on the line or the line above:
///
/// ```dart
/// SafeArea(child: ListView(...)) // layout-check: ignore wrapped-scrollable
/// ```
///
/// Two rules name widgets of a UI package (`pane-under-pinned-header`, `bare-header-in-scroll`:
/// `SliverScreenHeader`, `ScreenHeader`, `SliverContentPane`, `SliverContentFill`). They are inert
/// where those names are not used.
///
/// Settings: `dev_tool.layout_check` in `pubspec.yaml` (`config.dart`).
// ignore_for_file: avoid-high-cyclomatic-complexity, avoid-substring, prefer-for-in
library;

import 'dart:convert';
import 'dart:io';

import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/config.dart';

/// One thing worth stopping a build for: where it is, which rule, and the line that tripped it.
typedef Finding = ({String file, int line, String rule, String text});

/// Scans the repository at [root] (the current directory by default, which is the package root
/// under `dart test` and `flutter test`) and returns everything worth stopping a build for.
///
/// [settings] default to `dev_tool.layout_check` of the root's `pubspec.yaml`, or to the defaults
/// where there is no pubspec. Called in-process on purpose: a `dart run` from a test costs a compile
/// and a whole tree walk in a process already competing with the suite for cores.
List<Finding> scanProject([Directory? root, LayoutCheck? settings]) {
  final base = root ?? Directory.current;
  final config =
      settings ??
      (File('${base.path}/pubspec.yaml').existsSync() ? loadConfig(base.path).layoutCheck : const LayoutCheck());
  final wrappers = <String>[..._kWrappers, ...config.boxWrappers];
  final findings = <Finding>[];

  for (final path in config.paths) {
    final directory = Directory('${base.path}/$path');
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final relative = file.path.replaceAll(r'\', '/').substring(base.path.replaceAll(r'\', '/').length + 1);
      if (config.exclude.any(relative.contains)) continue;
      findings.addAll(_scan(relative, file.readAsStringSync(), wrappers, config.disable));
    }
  }
  return findings;
}

/// `layout_check [--root <dir>] [--json]`: prints what [scanProject] finds; exit 1 on any finding.
int runLayoutCheck(List<String> args) {
  final parser = commandParser()..addFlag('json', negatable: false, help: 'Print the findings as one JSON object.');
  final results = parseArgs(parser, args, 'layout_check [--root <dir>] [--json]');
  final findings = scanProject(Directory(rootOf(results)));

  if (results.flag('json')) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'findings': <Object?>[
          for (final finding in findings)
            <String, Object?>{'file': finding.file, 'line': finding.line, 'rule': finding.rule, 'text': finding.text},
        ],
      }),
    );
  } else {
    for (final finding in findings) {
      stdout.writeln('${finding.file}:${finding.line}: ${finding.rule} - ${finding.text.trim()}');
    }
    stdout.writeln(
      findings.isEmpty
          ? 'layout check: clean'
          : 'layout check: ${findings.length} finding(s). A false positive is silenced with '
                '`// layout-check: ignore <rule>` on the line or the line above.',
    );
  }
  return findings.isEmpty ? 0 : 1;
}

/// Everything scrollable, by the name it is constructed with.
const _kScrollables = <String>[
  'ListView',
  'GridView',
  'CustomScrollView',
  'SingleChildScrollView',
  'ReorderableListView',
  'NestedScrollView',
  'PageView',
  'ListWheelScrollView',
  'Scrollbar',
];

/// Stream methods that return a NEW object with no `==`.
///
/// `StreamController.stream` is deliberately absent: `_ControllerStream` overrides `==` on the
/// controller, so two reads of the same getter compare equal and nothing resubscribes.
const _kTransformers =
    'map|where|expand|asyncMap|asyncExpand|distinct|handleError|asBroadcastStream|timeout|transform|cast';

/// `ScreenHeader(` and `ScreenHeader.headline(`, never `SliverScreenHeader`, which is the fix.
final _kBareHeader = RegExp(r'(?<![A-Za-z])ScreenHeader(?:\.headline)?\(');

/// The panes that must not take the status bar a second time under a pinned header.
final _kPane = RegExp(r'(?<![A-Za-z])SliverContent(?:Pane|Fill)\(');

/// A top-level class declaration. `dart format` puts these at column zero, which is what makes
/// splitting a file on them reliable.
final _kDeclaration = RegExp(r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|mixin\s+)*class\s+(\w+)');

/// Box widgets that shrink whatever they contain: a scrollable inside one has a viewport smaller
/// than the space it was given. Flutter's own, and the two of a UI package's shared vocabulary; a
/// repository names its other box widgets in `dev_tool.layout_check.box_wrappers`.
const _kWrappers = <String>[
  'Padding',
  'SafeArea',
  'Center',
  'Align',
  'ConstrainedBox',
  'SizedBox',
  'FittedBox',
  'ContentPane',
  'MessageBody',
];

/// Every rule, applied line by line.
///
/// Line-based on purpose: `dart format` breaks a wrapper and its child across lines, so `Wrapper(`
/// on one line and the scrollable on the next is the shape that occurs, and a short window catches
/// it without parsing.
List<Finding> _scan(String file, String source, List<String> wrappers, List<String> disabled) {
  final lines = source.split('\n');
  final findings = <Finding>[];
  // Both markers are matched against a LINE, never against the whole source: a file that merely
  // mentions the opt-out marker in prose would otherwise exempt itself from every rule below.
  final generated = source.startsWith('// GENERATED') || lines.any((line) => line.trim() == '// coverage:ignore-file');
  if (generated) return findings;

  for (final (index, line) in lines.indexed) {
    final next = lines.elementAtOrNull(index + 1) ?? '';
    // The ignore may sit on the line ABOVE, where Dart's own `// ignore:` goes and where a formatter
    // pushes a long one anyway.
    final previous = index == 0 ? '' : (lines.elementAtOrNull(index - 1) ?? '');
    final window = '$previous\n$line\n$next';
    if (line.trimLeft().startsWith('//')) continue;

    void report(String rule, [String? text]) {
      if (disabled.contains(rule)) return;
      if (window.contains('layout-check: ignore $rule')) return;
      findings.add((file: file, line: index + 1, rule: rule, text: text ?? line));
    }

    // 1. A box wrapper whose OWN child is a scrollable. Read through the wrapper's argument list by
    //    bracket depth, so the child may sit any number of lines down (a `padding:` between them hid
    //    it from a two-line window) and a sibling's `child:` after the wrapper closed is not taken
    //    for the wrapper's.
    for (final wrapper in wrappers) {
      final opener = RegExp('(^|[^A-Za-z0-9_])$wrapper\\(').firstMatch(line);
      if (opener == null) continue;
      final ahead = lines.sublist(
        index,
        index + _kArgumentWindow > lines.length ? lines.length : index + _kArgumentWindow,
      );
      final text = ahead.map(_uncommented).join('\n');
      final own = _ownArguments(text, text.indexOf('(', opener.start));
      if (!_kScrollables.any((s) => RegExp('child:\\s*(?:const\\s+)?$s\\b').hasMatch(own))) continue;
      // A box that only fixes the cross axis of a horizontal strip gives it the height it scrolls
      // across; the viewport still spans the row. The direction is read from the scrollable's OWN
      // arguments: a horizontal sibling within the window must not exempt a vertical list.
      final child = _childArguments(text, text.indexOf('(', opener.start));
      final strip =
          wrapper == 'SizedBox' &&
          own.contains('height:') &&
          !own.contains('width:') &&
          RegExp(r'scrollDirection:\s*(?:Axis)?\.horizontal').hasMatch(child);
      if (!strip) report('wrapped-scrollable');
    }

    // 2. Reshaping: the same child at two different depths.
    if (RegExp(r'^\s*\w+\s*=\s*\w+\(\s*$').hasMatch(line) && RegExp(r'child:\s*\w+\s*[,)]').hasMatch(next)) {
      report('reshape');
    }
    if (RegExp(r'\?\s*\w+\(\s*child:\s*(\w+)\s*\)\s*:\s*\1\b').hasMatch(line)) report('reshape');
    if (RegExp(r'\?\s*\w+\(\s*child:\s*(\w+)\s*\)\s*:\s*\w+\(\s*child:\s*\1\s*\)').hasMatch(line)) report('reshape');
    // A variable re-wrapped in itself under an `if`, and a ternary whose one arm is the other arm
    // wrapped.
    final joined = _uncommented(line);
    if (RegExp(r'\bif\s*\(.*\)\s*(\w+)\s*=\s*\w+\(.*child:\s*\1\s*[,)]').hasMatch(joined)) report('reshape');
    if (RegExp(r'\?\s*(\w+)\s*:\s*\w+\(.*child:\s*\1\s*[,)]').hasMatch(joined)) report('reshape');

    // 3. A TRANSFORMED stream built where it is read.
    //
    //    Not `controller.stream`: that hands back a new `_ControllerStream` per access, but the class
    //    overrides `==` to compare controllers, so `StreamBuilder.didUpdateWidget` sees the same
    //    stream and keeps its subscription (measured 2026-09-04). What has no `==` is whatever the
    //    transformers return: a builder handed one cancels, resets its snapshot and resubscribes on
    //    every rebuild of its parent.
    if (line.contains('Builder') && RegExp('stream:\\s*[^,]*\\.($_kTransformers)\\(').hasMatch(line)) {
      report('stream-transform');
    }
    if (RegExp('Stream<[^>]+>\\s+get\\s+\\w+\\s*=>[^;]*\\.($_kTransformers)\\(').hasMatch(line)) {
      report('stream-transform');
    }

    // 4. A Paint inside a TextStyle: TextStyle compares `foreground` by identity, so the text
    //    re-shapes on every build.
    // The rule's own text matches the rule. layout-check: ignore paint-in-style
    if (line.contains('foreground:') && window.contains('Paint()')) report('paint-in-style');

    // 5. Wall-clock reads inside a builder.
    if (line.contains('DateTime.now()') &&
        _within(lines, index, RegExp(r'(Widget\s+build\(|itemBuilder:|builder:\s*\()'))) {
      report('clock-in-build');
    }

    // 6. Things with a dedicated, cheaper form.
    // The rule's own text matches the rule. layout-check: ignore media-query-of
    if (line.contains('MediaQuery.of(')) report('media-query-of');
    if (RegExp(r'\bshrinkWrap:\s*true').hasMatch(line)) report('shrink-wrap');
    if (RegExp(r'\bIntrinsic(Height|Width)\(').hasMatch(line)) report('intrinsic');
    if (RegExp(r'key:\s*UniqueKey\(\)').hasMatch(line)) report('unique-key-in-build');

    // 7. A pane under a pinned header taking the status bar a second time. The header covers the
    //    status bar; a pane that insets again sits a status bar too low.
    if (line.contains('SliverScreenHeader')) {
      for (var ahead = index + 1; ahead < lines.length && ahead < index + 30; ahead++) {
        final candidate = lines.elementAtOrNull(ahead) ?? '';
        if (!_kPane.hasMatch(_uncommented(candidate))) continue;
        final end = ahead + 6 > lines.length ? lines.length : ahead + 6;
        if (!lines.sublist(ahead, end).join('\n').contains('top: false')) {
          report('pane-under-pinned-header', candidate);
        }
        break;
      }
    }
  }

  // 8. A widget that builds a scrollable must not also build a bare `ScreenHeader`: written as a row
  //    the scroll owns, the header, and the back arrow with it, is gone after one flick. Per
  //    DECLARATION, because a dedicated header widget beside a scrolling body is the fix.
  if (!disabled.contains('bare-header-in-scroll')) {
    var owner = '<file>';
    var from = 0;
    void close(int to) {
      final declaration = lines.sublist(from, to);
      final block = declaration.map(_uncommented).join('\n');
      if (!_kScrollables.any((s) => block.contains('$s(')) || !_kBareHeader.hasMatch(block)) return;
      // Searched in the RAW lines: `block` has had every comment stripped, so an ignore written where
      // the convention puts it, in a comment, could never be found there.
      if (declaration.any((line) => line.contains('layout-check: ignore bare-header-in-scroll'))) {
        return;
      }
      findings.add((file: file, line: from + 1, rule: 'bare-header-in-scroll', text: owner));
    }

    for (final (index, line) in lines.indexed) {
      final match = _kDeclaration.firstMatch(line);
      if (match == null) continue;
      close(index);
      owner = match.group(1) ?? '<file>';
      from = index;
    }
    close(lines.length);
  }

  return findings;
}

/// How many lines a wrapper's argument list is read across. Past this a wrapper is far from its
/// child, which a formatter does not produce; and a whole-file scan per wrapper ran past 300 s.
const _kArgumentWindow = 8;

/// The text of the argument list whose `(` is at [open], at its own depth only: what nested calls
/// pass is dropped, so `child: ListView(...)` reads as `child: ListView`.
String _ownArguments(String text, int open) {
  if (open < 0) return '';
  final own = StringBuffer();
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final char = text[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
      if (depth == 1) continue;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
      if (depth == 0) break;
    }
    if (depth == 1) own.write(char);
  }
  return own.toString();
}

/// The argument list of the call passed as `child:` to the call whose `(` is at [open], at that
/// call's own depth; empty when there is none.
String _childArguments(String text, int open) {
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final char = text[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
      if (depth == 0) return '';
    } else if (depth == 1 && text.startsWith('child:', i)) {
      return _ownArguments(text, text.indexOf('(', i));
    }
  }
  return '';
}

/// [line] with its `//` tail removed, so prose ABOUT a widget is not a use of it.
String _uncommented(String line) => line.split('//').firstOrNull ?? line;

/// Whether one of the last few lines before [index] opens a build-like scope.
bool _within(List<String> lines, int index, RegExp opener) {
  for (var back = index; back >= 0 && back > index - 40; back--) {
    // A callback between here and the builder means this line runs on a TAP, not on a build: a date
    // picker reading the clock inside `onTap` was reported, and a check whose findings have to be
    // argued with is a check somebody switches off. Checked first, so the nearest opener wins.
    final above = lines.elementAtOrNull(back) ?? '';
    if (_kCallbackOpener.hasMatch(above)) return false;
    if (opener.hasMatch(above)) return true;
    // Another member of the class: the build above it is not where this line runs.
    if (back < index && _kMemberSignature.hasMatch(above)) return false;
  }
  return false;
}

/// A class member's signature at the formatter's two-space indent: `int _left() {`,
/// `String get label =>`. A build opener is tested before this, so it never stops the scan.
/// Exactly two spaces: a local function deeper in (`    String stamp() {`) runs inside the build,
/// and stopping there hid a clock read in it.
final _kMemberSignature = RegExp(
  r'^  (?! )(?:static\s+)?[\w<>?, ]*?\b[a-z_]\w*(?:\([^)]*\))?\s*(?:async\s*)?(?:\{|=>)\s*$'
  r'|^  (?! )[\w<>?, ]+\s+get\s+\w+\s*(?:=>|\{)',
);

/// The start of a callback body. Code below one of these runs on a gesture, not on a build.
final _kCallbackOpener = RegExp(
  r'on[A-Z]\w*:\s*\(|\bonTap:|\bonPressed:|\bonLongPress:|\bonSubmitted:|\bonSelected:',
);
