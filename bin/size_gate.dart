import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/size_gate.dart';

Future<void> main(List<String> args) => runMain(() => runSizeGate(args));
