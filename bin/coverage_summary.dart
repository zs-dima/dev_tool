import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/coverage_summary.dart';

Future<void> main(List<String> args) => runMain(() => runCoverageSummary(args));
