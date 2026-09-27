import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/test_workspace.dart';

Future<void> main(List<String> args) => runMain(() => runTestWorkspace(args));
