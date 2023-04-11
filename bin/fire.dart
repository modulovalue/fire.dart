import 'dart:async';
import 'dart:io' show File, FileSystemEntity, exit, stdout;

import 'package:fire/fire.dart' show run_fire;
import 'package:fire/io_impl.dart';
import 'package:path/path.dart' as path;

// TODO assertions seem to not be enabled when ran through fire, test.
// TODO support a test mode where arguments that are recognized by pkg:test
// TODO  are being passed to the dart process for better output.
Future<void> main(
  final List<String> args,
) async {
  if (args.isEmpty) {
    print("> usage: fire file.dart [arguments].");
    exit(1);
  } else {
    final file_path = args[0];
    if (FileSystemEntity.isFileSync(file_path)) {
      await run_fire(
        delegate: FireOutputDelegateIOImpl(
          file_path: file_path,
          file_path_file: File(file_path),
          output_path: path.setExtension(file_path, ".dill"),
          kernel_path: "lib/_internal/vm_platform_strong.dill",
          args: [
            if (args.isNotEmpty) ...args.sublist(1, args.length),
          ],
          output: stdout.writeln,
        ),
      );
    } else {
      print("'" + file_path + "' not found or isn't a file.");
      exit(2);
    }
  }
}
