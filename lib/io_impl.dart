import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io'
    show File, Platform, Process, ProcessResult, StdinException, stdin;

import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:stack_trace/stack_trace.dart';

import 'fire.dart' show FireOutputDelegate;
import 'fire.dart';
import 'util.dart';

class FireOutputDelegateIOImpl implements FireOutputDelegate {
  @override
  final String file_path;
  @override
  final String output_path;
  @override
  final String kernel_path;
  @override
  final List<String> args;
  final void Function(String) output;
  final File file_path_file;

  const FireOutputDelegateIOImpl({
    required this.output,
    required this.file_path_file,
    required this.file_path,
    required this.output_path,
    required this.kernel_path,
    required this.args,
  });

  @override
  void output_error(
    final Object payload,
    final StackTrace stack_trace,
  ) {
    output(payload.toString());
    output(Trace.format(stack_trace));
  }

  @override
  void output_string(
    final String str,
  ) {
    output(str);
  }

  @override
  void output_compiler_output(
    final String prefix,
    final Iterable<String> values,
  ) {
    output_string(prefix);
    if (values.isNotEmpty) {
      output(white_terminal("┏━━ Compiler output"));
      for (final line in values) {
        output(line);
      }
      output(white_terminal("┗━━ End"));
    }
  }

  @override
  Future<void> handle_input({
    required final FutureOr<void> Function() on_restart,
    required final FutureOr<void> Function() on_clear_restart,
    required final FutureOr<void> Function() on_frozen_restart,
    required final FutureOr<void> Function() on_enable_auto_restart,
    required final FutureOr<void> Function() on_disable_auto_restart,
    required final FutureOr<void> Function() on_panic_mode,
    required final FutureOr<void> Function() on_quit,
    required final FutureOr<void> Function() on_output_debug_information,
  }) async {
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } on StdinException {
      // This exception is thrown e.g. when run via the intellij UI:
      // 'OS Error: Inappropriate ioctl for device, errno = 25'
      // We ignore this for now as disabling echoMode and lineMode
      // is 'nice to have' but not necessary.
    }
    // The order of insertion below determines the order
    // inside of the help command and is roughly ordered
    // by importance to a potential user.
    final commands = <String, _Command>{};
    commands.addAll(
      {
        "r": _Command(
          help_text: " - press 'r' to hot restart.",
          action: on_restart,
        ),
        // On a lowercase 's' we clear the screen and hot restart.
        "s": _Command(
          help_text: " - press 's' to clear the screen and then hot restart.",
          action: on_clear_restart,
        ),
        // On a lowercase 'm' we enable a mode where the whole program
        // is restarted when a dart file file has been modified.
        // 'm' and 'n' are separate commands and not a single toggle to
        // give each command idempotency which improves UX.
        "m": _Command(
          help_text:
              " - press 'm' to enable auto restarting on a changes to dart files.",
          action: on_enable_auto_restart,
        ),
        // On a lowercase 'n' we disable the auto restart mode.
        // 'm' and 'n' are separate commands and not a single toggle to
        // give each command idempotency which improves UX.
        "n": _Command(
          help_text: " - press 'n' to disable auto restarting.",
          action: on_disable_auto_restart,
        ),
        // On a lowercase 'u' we restart the application into a frozen debug mode.
        "u": _Command(
          help_text: " - press 'u' to hot restart into debug mode.",
          action: on_frozen_restart,
        ),
        // On a lowercase 'h' we output a tutorial.
        "h": _Command(
          help_text: " - press 'h' to output a tutorial.",
          action: () {
            // We print a tutorial on a lowercase 'h'.
            output_string("fire.dart tutorial:");
            for (final command in commands.entries) {
              final text = command.value.help_text;
              if (text != null) {
                output_string(text);
              }
            }
          },
        ),
        // We stop the current running application on a single lowercase 'p'.
        "p": _Command(
          help_text:
              " - press 'p' to engage panic mode which stops the current "
              "application. (useful for when it doesn't terminate)",
          action: on_panic_mode,
        ),
        // We quit fire on a single lowercase 'q'.
        "q": _Command(
          // The terminal has its own mechanisms for
          // exiting programs so this shouldn't be needed.
          help_text: null,
          action: on_quit,
        ),
        // We print debug information on a lowercase 'd'.
        "d": _Command(
          // Users usually won't need this.
          help_text: " - press 'd' to view debug information.",
          action: on_output_debug_information,
        ),
        "": _Command(
          help_text: null,
          action: () {
            // We ignore empty output i.e. newlines.
            // Why? It is common to 'spam' the terminal with
            // newlines to introduce a bunch of empty
            // lines as an ad-hoc way to clear the terminal.
            // These empty lines serve as a visual divider between
            // previous output and new output which improves the UX.
          },
        ),
      },
    );
    await for (final bytes in stdin) {
      final input = String.fromCharCodes(bytes).trimRight();
      final command = commands.typed_get(input);
      if (command == null) {
        output_string(
          "> invalid input, got '" +
              input +
              "', consider pressing 'h' for help.",
        );
      } else {
        await command.action();
      }
    }
  }

  static String white_terminal(
    final String text,
  ) {
    return '\x1b[37m' + text + '\x1b[0m';
  }

  @override
  Future<void> run_dart() async {
    output(white_terminal("┏━━ Program output"));
    final ran = await measure_in_ms<ProcessResult>(
      fn: () {
        // TODO run an asynchronous process so that the output is reported as soon as it is available.
        // TODO make sure that only one process can be running.
        final process = Process.runSync(
          path.normalize(Platform.resolvedExecutable),
          [
            "--enable-asserts",
            output_path,
            ...args,
          ],
          // We set the working directory of the to-be-executed
          // file to the directory of the file itself.
          // Another reasonable choice for this could have
          // been the root of the package.
          // Setting it to the file itself is more useful IMHO,
          // because IO APIs will work relative to the file and
          // not relative to be package root (which is what happens
          // with e.g. the first party "dart" CLI tool.)
          workingDirectory: file_path_file.parent.path,
        );
        // TODO listen to stdout and stderr and redirect lines to 'output'.
        if (process.stdout != null) {
          for (final line
              in LineSplitter.split(process.stdout.toString().trimRight())) {
            // output(white_terminal("┃ >") + line);
            output(line);
          }
        }
        if (process.stderr != null) {
          for (final line
              in LineSplitter.split(process.stderr.toString().trimRight())) {
            // output(white_terminal("┃ >") + line);
            output(line);
          }
        }
        return process;
      },
    );
    output(white_terminal("┗━━ End"));
    // TODO output whether the output emitted any errors.
    output(white_terminal(ran.key));
  }

  @override
  void output_welcome_screen() {
    String terminal_green(
      final String text,
    ) {
      return '\x1b[32m' + text + '\x1b[0m';
    }

    output_string(
        terminal_green("Welcome to fire.dart " + _fire_emoji + " press 'h' for help."));
  }

  @override
  void output_clear_screen() {
    for (int i = 0; i < 15; i++) {
      output_string("");
    }
    output_string(_fire_emoji * 40);
    output_string("");
  }
}

const _fire_emoji = "🔥";

// region internal
class _Command {
  final String? help_text;
  final FutureOr<void> Function() action;

  const _Command({
    required this.help_text,
    required this.action,
  });
}
// endregion
