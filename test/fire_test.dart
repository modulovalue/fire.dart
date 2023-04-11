// This isn't using package:test due to some version related
// weirdness and to minimize the amount of dependencies.
void main() {
  _TestSuite.all();
}

// TODO cache dir create a fire cache dir.
// TODO cache dir delete that fire cache dir.
// TODO cache dir create an empty package
abstract class _TestSuite {
  static void all() {
    can_restart_programs();
    can_restart_unchanged_programs();
    programs_that_fail_to_compile_do_not_cause_a_crash();
    panic_mode_can_quit_programs_that_dont_terminate();
    programs_that_have_been_repaired_do_reload_correctly();
    assertions_are_enabled_when_ran_through_fire();
  }

  static void can_restart_programs() {
    // TODO simple test.
  }

  static void can_restart_unchanged_programs() {
    // TODO simple test.
  }

  static void programs_that_fail_to_compile_do_not_cause_a_crash() {
    // TODO load a valid program, then an invalid one
  }

  static void panic_mode_can_quit_programs_that_dont_terminate() {
    // TODO load a valid program, then an invalid one
  }

  static void programs_that_have_been_repaired_do_reload_correctly() {
    // TODO load a valid program, then an invalid one and then a valid one again.
  }

  static void assertions_are_enabled_when_ran_through_fire() {
    const test_file = """
void main() {
  assert(false, "?");
}
""";
    // TODO load a valid program with an assertion that fails and expect a failure.
    // TODO output must contain "Failed assertion:".
  }
}
