#!/usr/bin/env bats
# Tests for check_preview_support.sh — Flutter detection + version comparison.

load helpers

setup()    { pw_setup; }
teardown() { pw_teardown; }

@test "passes when stub flutter reports 3.38.0" {
  STUB_FLUTTER_VERSION=3.38.0 run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"3.38.0"* ]]
  [[ "$output" == *"supports widget previews"* ]]
}

@test "passes at the exact lower bound 3.35.0" {
  STUB_FLUTTER_VERSION=3.35.0 run_check
  [ "$status" -eq 0 ]
}

@test "passes for 3.35 with patch version" {
  STUB_FLUTTER_VERSION=3.35.4 run_check
  [ "$status" -eq 0 ]
}

@test "fails for 3.34.x (one minor below the floor)" {
  STUB_FLUTTER_VERSION=3.34.9 run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"too old"* ]]
  [[ "$output" == *"3.34.9"* ]]
  [[ "$output" == *"upgrade"* ]] || [[ "$output" == *"flutter upgrade"* ]]
}

@test "fails for an old major version" {
  STUB_FLUTTER_VERSION=2.10.5 run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"too old"* ]]
}

@test "tolerates pre-release suffix on the version string" {
  STUB_FLUTTER_VERSION="3.38.0-1.2.pre" run_check
  [ "$status" -eq 0 ]
}

@test "exit 1 when flutter --version produces no output" {
  STUB_FLUTTER_VERSION_BLANK=1 run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no output"* ]]
}

@test "exit 127 when no flutter binary is on PATH" {
  # Strip our stubs dir from PATH so `flutter` and `fvm` both vanish.
  PATH="/usr/bin:/bin" run_check
  [ "$status" -eq 127 ]
  [[ "$output" == *"Flutter not found"* ]]
}

@test "honors FLUTTER_BIN override (single token)" {
  FLUTTER_BIN="$PW_STUBS_DIR/flutter" STUB_FLUTTER_VERSION=3.36.0 run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"3.36.0"* ]]
}

@test "--quiet suppresses success message but still exits 0" {
  STUB_FLUTTER_VERSION=3.38.0 run_check --quiet
  [ "$status" -eq 0 ]
  [[ "$output" != *"supports widget previews"* ]]
}
