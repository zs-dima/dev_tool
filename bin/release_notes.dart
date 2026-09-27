import 'package:dev_tool/src/cli.dart';
import 'package:dev_tool/src/release_notes.dart';

Future<void> main(List<String> args) => runMain(() => runReleaseNotes(args));
