import 'package:dev_tool/dev_tool.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The `dev_tool:` block is read strictly: a key this version does not know, or a value of the wrong
/// shape, is an error naming it, because a typo that passed as a default would disable a check.
void main() {
  DevToolConfig parse(String yaml) => parseConfig((loadYaml(yaml) as YamlMap)['dev_tool']);

  Matcher refusedNaming(String text) =>
      throwsA(isA<UsageException>().having((e) => e.message, 'message', contains(text)));

  test('no block means the defaults: no extras, the default clock, no budget, no key', () {
    final config = parse('name: app\n');
    expect(config.extras, isEmpty);
    expect(config.clock('android'), equals(kDefaultClock));
    expect(config.sizeBudgetMb, isNull);
    expect(config.keys, isEmpty);
  });

  test('every setting is read', () {
    final config = parse('''
dev_tool:
  test:
    extra: [example, worker/]
  release:
    size_budget_mb: 90
    android: {build_number_base: 1788816828, build_number_t0: 1788869018}
  keys: [SENTRY_DSN, MAPS_KEY]
''');
    expect(config.extras, <String>['example', 'worker']);
    expect(config.sizeBudgetMb, 90);
    expect(config.clock('android'), (base: 1788816828, t0: 1788869018));
    expect(config.clock('ios'), kDefaultClock);
    expect(config.keys, <String>['SENTRY_DSN', 'MAPS_KEY']);
  });

  test('an unknown key is refused, at every level', () {
    expect(() => parse('dev_tool:\n  tests:\n    extra: [a]\n'), refusedNaming('dev_tool.tests'));
    expect(() => parse('dev_tool:\n  test:\n    extras: [a]\n'), refusedNaming('dev_tool.test.extras'));
    expect(
      () => parse('dev_tool:\n  release:\n    android: {base: 1, build_number_t0: 2}\n'),
      refusedNaming('dev_tool.release.android.base'),
    );
  });

  test('a value of the wrong shape is refused with what was expected', () {
    expect(() => parse('dev_tool:\n  test:\n    extra: example\n'), refusedNaming('a list of directories'));
    expect(
      () => parse('dev_tool:\n  release:\n    android: {build_number_base: 1, build_number_t0: soon}\n'),
      refusedNaming('build_number_t0 must be an integer (unix seconds), got "soon"'),
    );
    expect(
      () => parse('dev_tool:\n  release:\n    android: {build_number_base: 1}\n'),
      refusedNaming('build_number_t0'),
    );
    expect(() => parse('dev_tool:\n  release:\n    size_budget_mb: 0\n'), refusedNaming('a positive integer'));
    expect(() => parse('dev_tool:\n  release:\n    Android: {}\n'), refusedNaming('a platform name'));
    expect(() => parse('dev_tool:\n  keys: SENTRY_DSN\n'), refusedNaming('a list of variable names'));
  });

  test('an extra must stay inside the repository', () {
    expect(() => parse('dev_tool:\n  test:\n    extra: [../other]\n'), refusedNaming('inside the repository'));
    expect(() => parse('dev_tool:\n  test:\n    extra: [/abs]\n'), refusedNaming('inside the repository'));
  });
}
