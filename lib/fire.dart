import 'dart:async' show FutureOr, unawaited;
import 'dart:io' show Directory, File, exit;
import 'package:frontend_server_client/frontend_server_client.dart'
    show FrontendServerClient;
import 'package:path/path.dart' as path;
import 'package:watcher/watcher.dart' show DirectoryWatcher;

import 'util.dart' show measure_in_ms;

// TODO finish building a testsuite.
Future<void> run_fire({
  required final FireOutputDelegate delegate,
}) async {
  delegate.output_welcome_screen();
  final file_path_file = File(delegate.file_path);
  final root = _find(
    file: file_path_file,
    // This constant was taken from `FrontendServerClient.start`s
    // packageJson parameters default value.
    target: ".dart_tool/package_config.json",
  );
  _AutoRestartMode auto_restart_mode = _AutoRestartMode.none;
  final invalidated = <Uri>{};
  final compiler = _Compiler(
    client: await () async {
      try {
        return await FrontendServerClient.start(
          delegate.file_path,
          delegate.output_path,
          delegate.kernel_path,
          packagesJson: root.target,
        );
      } on Object catch (error, stack_trace) {
        delegate.output_error(error, stack_trace);
        return exit(3);
      }
    }(),
    invalidated_files: () => invalidated.toList(),
    clear_invalidated_files: () => invalidated.clear(),
    invalidated_is_empty: () => invalidated.isEmpty,
    output: delegate,
    run_program: () async {
      try {
        // TODO implement panic mode by maintaining a persistent background process
        // TODO  and make sure that only one process can be run at any given time.
        await delegate.run_dart();
      } on Object catch (error, stack_trace) {
        delegate.output_error(error, stack_trace);
      }
    },
  );
  // We watch the whole directory containing the .dart_tool directory.
  // We do this so that in addition to lib, directories like bin and
  // test an also contribute to the invalidation logic.
  final root_directory = root.root;
  final is_watching = await () async {
    if (root_directory.existsSync()) {
      final watcher = DirectoryWatcher(root_directory.absolute.path);
      // We don't cancel the subscription here because it
      // doesn't matter for this terminal application.
      // ignore: unused_local_variable, cancel_subscriptions
      final subscription = watcher.events.listen((final event) {
        // We only invalidate dart files because other file types
        // could cause performance issues and shouldn't be relevant
        // in the majority of cases where fire.dart is being used.
        if (event.path.endsWith(".dart")) {
          delegate.output_string("> watcher: " + event.toString());
          final invalidate = path.toUri(event.path);
          invalidated.add(invalidate);
          switch (auto_restart_mode) {
            case _AutoRestartMode.none:
              break;
            case _AutoRestartMode.on_file_changed:
              unawaited(compiler.clear_restart(name: "auto restarting"));
          }
        }
      });
      await watcher.ready;
      return true;
    } else {
      delegate.output_string("> not watching the root directory.");
      return false;
    }
  }();
  await compiler.restart_run(
    name: "compiling",
  );
  await delegate.handle_input(
    on_restart: () => compiler.restart_run(name: "restarting"),
    on_clear_restart: () => compiler.clear_restart(name: "restarting"),
    on_quit: () => compiler.shutdown(),
    on_frozen_restart: () {
      // TODO implement a debug mode that starts an application with frozen
      // TODO  isolates until a debugger instance has connected to the program.
    },
    on_panic_mode: () {
      // This is useful for when it is stuck in an infinite loop.
      // TODO implement panic mode, which stops the current application
      // TODO report that panic mode has been engaged.
    },
    on_enable_auto_restart: () {
      switch (auto_restart_mode) {
        case _AutoRestartMode.none:
          auto_restart_mode = _AutoRestartMode.on_file_changed;
          delegate.output_string("> You have enabled auto restart.");
          break;
        case _AutoRestartMode.on_file_changed:
          delegate.output_string("> Auto restart is already enabled.");
          break;
      }
    },
    on_disable_auto_restart: () {
      switch (auto_restart_mode) {
        case _AutoRestartMode.none:
          delegate.output_string("> Auto restart is already disabled.");
          break;
        case _AutoRestartMode.on_file_changed:
          auto_restart_mode = _AutoRestartMode.none;
          delegate.output_string("> You have disabled auto restart.");
          break;
      }
    },
    on_output_debug_information: () {
      delegate.output_string("fire.dart debug state:");
      delegate.output_string("Arguments:");
      delegate.output_string(" • File path: " + delegate.file_path);
      delegate.output_string(" • Output path: " + delegate.output_path);
      delegate.output_string(" • Kernel path: " + delegate.kernel_path);
      delegate.output_string(" • Args: " + delegate.args.toString());
      delegate.output_string("Auto restarting:");
      delegate.output_string(" • Mode: " + auto_restart_mode.toString());
      delegate.output_string("Root:");
      delegate.output_string(" • Detected root: " + root.root.toString());
      delegate.output_string(" • Detected package_config.json: " + root.target);
      delegate.output_string("Watcher:");
      delegate.output_string(" • Watched directory: " + root_directory.path);
      delegate.output_string(" • Active: " + is_watching.toString());
      delegate.output_string(" • Invalidated files (" + invalidated.length.toString() + ")");
      for (final uri in invalidated) {
        delegate.output_string("   - " + uri.toString());
      }
    },
  );
}

abstract class FireOutputDelegate {
  String get file_path;

  String get output_path;

  String get kernel_path;

  List<String> get args;

  void output_string(
    final String str,
  );

  void output_error(
    final Object payload,
    final StackTrace stack_trace,
  );

  void output_compiler_output(
    final String prefix,
    final Iterable<String> values,
  );

  Future<void> run_dart();

  Future<void> handle_input({
    required final FutureOr<void> Function() on_restart,
    required final FutureOr<void> Function() on_clear_restart,
    required final FutureOr<void> Function() on_frozen_restart,
    required final FutureOr<void> Function() on_enable_auto_restart,
    required final FutureOr<void> Function() on_disable_auto_restart,
    required final FutureOr<void> Function() on_panic_mode,
    required final FutureOr<void> Function() on_quit,
    required final FutureOr<void> Function() on_output_debug_information,
  });

  void output_welcome_screen();

  void output_clear_screen();
}

// region internal
class _Compiler {
  final FrontendServerClient client;
  final FireOutputDelegate output;
  final bool Function() invalidated_is_empty;
  final void Function() clear_invalidated_files;
  final List<Uri> Function() invalidated_files;
  final Future<void> Function() run_program;

  _Compiler({
    required this.client,
    required this.run_program,
    required this.output,
    required this.invalidated_files,
    required this.invalidated_is_empty,
    required this.clear_invalidated_files,
  });

  bool _is_first_run = true;
  bool is_compiling = false;

  Future<void> restart_run({
    required final String name,
  }) async {
    Future<bool> _restart() async {
      try {
        if (is_compiling) {
          output.output_string(
              "> A program is currently being compiled, please wait.");
          return false;
        } else {
          is_compiling = true;
          final result = await client.compile(
            invalidated_files(),
          );
          is_compiling = false;
          // Note: calling client.reject seems to never work properly.
          // Calling 'accept' followed by a 'reset' seem to always
          // work correctly.
          client.accept();
          client.reset();
          if (result.dillOutput == null) {
            // It's not clear when this will happen.
            output.output_string("> no compilation result, rejecting.");
            return false;
          } else {
            if (result.errorCount > 0) {
              output.output_compiler_output(
                "> ❌ compiled with " +
                    result.errorCount.toString() +
                    " error(s).",
                result.compilerOutputLines,
              );
              return false;
            } else {
              output.output_compiler_output(
                "> ✅ compiled with no errors.",
                result.compilerOutputLines,
              );
              // We only clear the invalidated files on a success so that
              // Invalidated files that have not been compiled correctly
              // will be included in the next compilation attempt.
              clear_invalidated_files();
              return true;
            }
          }
        }
      } on Object catch (error, stack_trace) {
        is_compiling = false;
        client.accept();
        client.reset();
        // 'reject' throws if a compilation failed so we
        // just don't reject here even if the docs say we should.
        output.output_error(error, stack_trace);
        return false;
      }
    }

    output.output_string("> " + name + "...");
    final restart_duration = await measure_in_ms<bool>(
      fn: () async {
        if (_is_first_run) {
          _is_first_run = false;
          return _restart();
        } else {
          if (invalidated_is_empty()) {
            // Restarting is not necessary since nothing has changed
            // so we just assume that restarting succeeded.
            return true;
          } else {
            return _restart();
          }
        }
      },
    );
    // TODO append this message to the compiled with ... message above.
    output.output_string("> done, took " + restart_duration.key);
    if (restart_duration.value) {
      await run_program();
    }
  }

  Future<void> clear_restart({
    required final String name,
  }) {
    output.output_clear_screen();
    return restart_run(name: name);
  }

  Future<Never> shutdown() async {
    final exit_code = await client.shutdown();
    exit(exit_code);
  }
}

enum _AutoRestartMode {
  /// Never restart automatically.
  none,

  /// Restart fire when the main file changed.
  on_file_changed,
}

_DiscoveredRoot _find({
  required final File file,
  required final String target,
}) {
  // Start out at the directive where the given file is contained.
  Directory current = file.parent.absolute;
  for (;;) {
    // Construct a candidate where the file we are looking for could be.
    final candidate = File(path.join(current.path, target));
    final file_found = candidate.existsSync();
    if (file_found) {
      // If the file has been found, return its path.
      return _DiscoveredRoot(
        target: candidate.absolute.path,
        root: current.absolute,
      );
    } else {
      // The file has not been found.
      // Walk up the current directory until
      // the root directory has been reached
      final parent = current.parent;
      final root_directory_reached = current == parent;
      if (root_directory_reached) {
        // package_config not found.
        return _DiscoveredRoot(
          target: target,
          root: current.absolute,
        );
      } else {
        // Go to the parent until the
        // rootDirectory has been reached.
        current = parent;
      }
    }
  }
}

class _DiscoveredRoot {
  final String target;
  final Directory root;

  const _DiscoveredRoot({
    required this.target,
    required this.root,
  });
}
// endregion
