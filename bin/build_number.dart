import 'package:dev_tool/src/build_number.dart';
import 'package:dev_tool/src/cli.dart';

Future<void> main(List<String> args) => runMain(() => runBuildNumber(args));
