import 'dart:io';

import 'package:dev_tool/dev_tool.dart';
import 'package:dev_tool/src/layout_check.dart' show runLayoutCheck;
import 'package:test/test.dart';

/// One fixture per rule, each written to a throwaway project the checker then scans.
///
/// The checker is regex over source with no package resolution, so a fixture is a `.dart` FILE and
/// nothing else — it never has to compile. What each case proves is that the rule fires on the
/// shape it names and stays silent on the shape that fixes it; a rule that cannot fail proves
/// nothing, so every case carries its own negative.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('layout_check'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Writes [source] as the project's one file and returns the rules that fired.
  List<String> rulesFor(String source) {
    Directory('${root.path}/lib').createSync(recursive: true);
    File('${root.path}/lib/fixture.dart').writeAsStringSync(source);

    return scanProject(root).map((finding) => finding.rule).toList();
  }

  test('a box wrapper around a scrollable is reported, and the sliver form is not', () {
    expect(rulesFor('Widget x() => Padding(\n  child: ListView(),\n);'), contains('wrapped-scrollable'));
    expect(rulesFor('Widget x() => CustomScrollView(\n  slivers: <Widget>[],\n);'), isEmpty);
  });

  // Case by case, each with the shape that fixes it: the rule used to read one line past the
  // wrapper, so a `padding:` between wrapper and child hid the scrollable, and a sibling's `child:`
  // on the next line was taken for the wrapper's.
  test('a wrapped scrollable is found however many lines down its child is', () {
    const deep = '''
Widget x() => Padding(
  padding: p,
  child: ListView(),
);
''';
    expect(rulesFor(deep), contains('wrapped-scrollable'));
  });

  test("a sibling's child is not the wrapper's", () {
    const sibling = '''
Widget x() => DecoratedBox(
  decoration: Padding(padding: p),
  child: ListView(),
);
''';
    expect(rulesFor(sibling), isEmpty);
  });

  test('a height-only box around a horizontal strip is not a wrapped scrollable', () {
    const strip = '''
Widget x() => SizedBox(
  height: 72,
  child: ListView.separated(
    scrollDirection: .horizontal,
    itemBuilder: b,
  ),
);
''';
    const vertical = '''
Widget x() => SizedBox(
  height: 72,
  child: ListView.separated(
    itemBuilder: b,
  ),
);
''';
    expect(rulesFor(strip), isEmpty);
    expect(rulesFor(vertical), contains('wrapped-scrollable'));
  });

  test('a horizontal sibling does not exempt a vertical list', () {
    const sibling = '''
Widget x() => Column(children: [
  SizedBox(
    height: 72,
    child: ListView(children: rows),
  ),
  Row(scrollDirection: .horizontal),
]);
''';
    expect(rulesFor(sibling), contains('wrapped-scrollable'));
  });

  // A local function of the build runs in the build. The back-scan stopped at any `name() {` line
  // at any indent and took it for a member of the class.
  test('a clock read inside a local function of build is still in build', () {
    const local = r'''
class _S extends State<W> {
  Widget build(BuildContext context) {
    String stamp() {
      return '${DateTime.now()}';
    }
    return Text(stamp());
  }
}
''';
    expect(rulesFor(local), contains('clock-in-build'));
  });

  test('the two reshape shapes are reported, and the value form is not', () {
    expect(
      rulesFor('void x() { if (cap != null) w = Center(child: ConstrainedBox(constraints: cap, child: w)); }'),
      contains('reshape'),
    );
    expect(
      rulesFor('Widget x() => enabled ? sized : Opacity(opacity: .38, child: IgnorePointer(child: sized));'),
      contains('reshape'),
    );
    expect(
      rulesFor(
        'Widget x() => Opacity(opacity: enabled ? 1 : .38, child: IgnorePointer(ignoring: !enabled, child: sized));',
      ),
      isEmpty,
    );
  });

  test('the clock read in another member below build is not a read in build', () {
    const member = '''
class _S extends State<W> {
  Widget build(BuildContext context) => const Text('x');

  int _left() {
    return until.difference(DateTime.now()).inSeconds;
  }
}
''';
    const inBuild = r'''
class _S extends State<W> {
  Widget build(BuildContext context) {
    return Text('${DateTime.now()}');
  }
}
''';
    expect(rulesFor(member), isEmpty);
    expect(rulesFor(inBuild), contains('clock-in-build'));
  });

  test('a subtree that changes shape on a condition is reported', () {
    expect(rulesFor('Widget x() => wide ? Pad(child: body) : body;'), contains('reshape'));
    expect(rulesFor('Widget x() => Pad(child: body);'), isEmpty);
  });

  test('a transformed stream built where it is read is reported', () {
    expect(
      rulesFor('Widget x() => StreamBuilder<int>(stream: source.map(read), builder: b);'),
      contains('stream-transform'),
    );
    expect(rulesFor('Widget x() => StreamBuilder<int>(stream: source, builder: b);'), isEmpty);
  });

  test('the cheaper forms are named', () {
    expect(rulesFor('final size = MediaQuery.of(context).size;'), contains('media-query-of'));
    expect(rulesFor('final list = ListView(shrinkWrap: true);'), contains('shrink-wrap'));
    expect(rulesFor('final box = IntrinsicHeight(child: row);'), contains('intrinsic'));
    expect(rulesFor('final row = Row(key: UniqueKey());'), contains('unique-key-in-build'));
    expect(rulesFor('final size = MediaQuery.sizeOf(context);'), isEmpty);
  });

  test('a bare ScreenHeader inside a scrolling widget is reported', () {
    const bad = '''
class BadScreen extends StatelessWidget {
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[SliverToBoxAdapter(child: ScreenHeader(label: 'x'))],
  );
}
''';
    // The fix: the header is pinned above the scroll view rather than carried inside it.
    const good = '''
class GoodScreen extends StatelessWidget {
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[SliverScreenHeader(label: 'x')],
  );
}
''';

    expect(rulesFor(bad), contains('bare-header-in-scroll'));
    expect(rulesFor(good), isEmpty);
  });

  test('the bare-header rule can actually be silenced', () {
    // The ignore is written in a comment, and the rule matched it against a block whose comments
    // had already been stripped - so it could never fire. Found by running the checker over the
    // gallery, where a component catalogue legitimately renders a ScreenHeader inside its scroll.
    const silenced = '''
class Catalogue extends StatelessWidget {
  // layout-check: ignore bare-header-in-scroll
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[SliverToBoxAdapter(child: ScreenHeader(label: 'x'))],
  );
}
''';

    expect(rulesFor(silenced), isEmpty);
  });

  test('a pane that takes the status bar under a pinned header is reported', () {
    const bad = '''
Widget x() => CustomScrollView(
  slivers: <Widget>[
    SliverScreenHeader(),
    SliverContentPane(sliver: sliver),
  ],
);
''';
    const good = '''
Widget x() => CustomScrollView(
  slivers: <Widget>[
    SliverScreenHeader(),
    SliverContentPane(
      top: false,
      sliver: sliver,
    ),
  ],
);
''';

    expect(rulesFor(bad), contains('pane-under-pinned-header'));
    expect(rulesFor(good), isEmpty);
  });

  test('a finding is silenced on the line, and only that finding', () {
    expect(rulesFor('final size = MediaQuery.of(context).size; // layout-check: ignore media-query-of'), isEmpty);
    expect(
      rulesFor('final size = MediaQuery.of(context).size; // layout-check: ignore shrink-wrap'),
      contains('media-query-of'),
    );
  });

  test('generated source is not scanned', () {
    expect(rulesFor('// GENERATED\nfinal size = MediaQuery.of(context).size;'), isEmpty);
    expect(rulesFor('// coverage:ignore-file\nfinal size = MediaQuery.of(context).size;'), isEmpty);
  });

  test('a file that only MENTIONS the opt-out marker is still scanned', () {
    // The marker used to be matched against the whole source, so a doc comment naming it exempted
    // the file from every rule - silently. The checker's own source was the proof: it named the
    // marker in its implementation and therefore never scanned itself.
    expect(
      rulesFor('/// Prose naming // coverage:ignore-file.\nfinal size = MediaQuery.of(context).size;'),
      contains('media-query-of'),
    );
    // Indentation still makes a real marker; the line must carry nothing else.
    expect(rulesFor('  // coverage:ignore-file\nfinal size = MediaQuery.of(context).size;'), isEmpty);
  });

  group('settings and the executable', () {
    void write(String path, String text) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    const wrapped = 'Widget x() => GlassCard(\n  child: ListView(),\n);';

    test("a repository's own box widget is a wrapper once dev_tool.layout_check names it", () {
      write('lib/a.dart', wrapped);
      expect(scanProject(root), isEmpty, reason: 'an unknown widget is not a box');

      write('pubspec.yaml', 'name: app\ndev_tool:\n  layout_check:\n    box_wrappers: [GlassCard]\n');
      expect(scanProject(root).map((finding) => finding.rule), equals(<String>['wrapped-scrollable']));
    });

    test('paths, disable and exclude are read from the pubspec', () {
      write('lib/a.dart', 'final size = MediaQuery.of(context).size;');
      write('example/lib/b.dart', 'final size = MediaQuery.of(context).size;');
      write('lib/skipped/c.dart', 'final size = MediaQuery.of(context).size;');
      write(
        'pubspec.yaml',
        'name: app\ndev_tool:\n  layout_check:\n    paths: [lib, example/lib]\n    exclude: [skipped/]\n',
      );
      expect(
        scanProject(root).map((finding) => finding.file).toSet(),
        equals(<String>{'lib/a.dart', 'example/lib/b.dart'}),
      );

      write('pubspec.yaml', 'name: app\ndev_tool:\n  layout_check:\n    disable: [media-query-of]\n');
      expect(scanProject(root), isEmpty);
    });

    test('settings handed in win over the pubspec', () {
      write('lib/a.dart', wrapped);
      write('pubspec.yaml', 'name: app\n');
      expect(scanProject(root, const LayoutCheck(boxWrappers: <String>['GlassCard'])), hasLength(1));
    });

    test('a rule or a widget name the check does not know is refused, naming the setting', () {
      Matcher refusedNaming(String text) =>
          throwsA(isA<UsageException>().having((e) => e.message, 'message', contains(text)));

      write('pubspec.yaml', 'name: app\ndev_tool:\n  layout_check:\n    disable: [shrinkwrap]\n');
      expect(() => scanProject(root), refusedNaming('dev_tool.layout_check.disable'));
      write('pubspec.yaml', 'name: app\ndev_tool:\n  layout_check:\n    box_wrappers: ["Glass(Card"]\n');
      expect(() => scanProject(root), refusedNaming('dev_tool.layout_check.box_wrappers'));
      write('pubspec.yaml', 'name: app\ndev_tool:\n  layout_check:\n    path: [lib]\n');
      expect(() => scanProject(root), refusedNaming('dev_tool.layout_check.path'));
    });

    test('the executable exits 0 on a clean tree and 1 on a finding', () {
      write('pubspec.yaml', 'name: app\n');
      write('lib/a.dart', 'Widget x() => const SizedBox();');
      expect(runLayoutCheck(<String>['--root', root.path]), isZero);

      write('lib/a.dart', 'final size = MediaQuery.of(context).size;');
      expect(runLayoutCheck(<String>['--root', root.path]), equals(1));
      expect(runLayoutCheck(<String>['--root', root.path, '--json']), equals(1));
    });

    test('every rule the settings may disable is a rule the scan can report', () {
      // One line per rule that trips it; a rule added to the list without a shape here fails.
      const shapes = <String, String>{
        'wrapped-scrollable': 'Widget x() => Padding(\n  child: ListView(),\n);',
        'reshape': 'final w = wide ? Center(child: body) : body;',
        'stream-transform': 'StreamBuilder(stream: source.map((e) => e), builder: b);',
        'paint-in-style': 'final s = TextStyle(foreground: Paint());',
        'clock-in-build': 'Widget build(BuildContext context) {\n  final now = DateTime.now();\n}',
        'media-query-of': 'final size = MediaQuery.of(context).size;',
        'shrink-wrap': 'final l = ListView(shrinkWrap: true);',
        'intrinsic': 'final h = IntrinsicHeight(child: c);',
        'unique-key-in-build': 'final k = SizedBox(key: UniqueKey());',
        'pane-under-pinned-header':
            'final s = <Widget>[\n  SliverScreenHeader(label: l),\n  SliverContentPane(sliver: s),\n];',
        'bare-header-in-scroll': 'class A extends StatelessWidget {\n  Widget build(BuildContext c) => ListView(children: [ScreenHeader(label: l)]);\n}',
      };
      expect(shapes.keys.toSet(), equals(kLayoutRules.toSet()));
      for (final MapEntry(key: rule, value: source) in shapes.entries) {
        expect(rulesFor(source), contains(rule), reason: rule);
      }
    });
  });
}
