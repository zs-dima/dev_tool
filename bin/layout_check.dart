import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/layout_check.dart';

Future<void> main(List<String> args) => runMain(() => runLayoutCheck(args));
