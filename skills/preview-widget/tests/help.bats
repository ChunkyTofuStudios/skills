#!/usr/bin/env bats
# Tests for --help / -h / arg-validation behavior across all four scripts.

load helpers

setup()    { pw_setup; }
teardown() { pw_teardown; }

@test "check_preview_support.sh --help prints usage" {
  run_check --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"FLUTTER_BIN"* ]]
}

@test "check_preview_support.sh -h prints usage" {
  run_check -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "check_preview_support.sh rejects unknown flags" {
  run_check --not-a-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "start_preview.sh --help prints usage" {
  run_start --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--stop"* ]]
  [[ "$output" == *"PREVIEW_WIDGET_STATE_DIR"* ]]
}

@test "start_preview.sh --timeout without a value errors out" {
  run_start --timeout
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing value"* ]]
}

@test "screenshot_preview.sh --help prints usage" {
  run_screenshot --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--out"* ]]
  [[ "$output" == *"--size"* ]]
  [[ "$output" == *"--wait"* ]]
}

@test "screenshot_preview.sh -o without a value errors out" {
  run_screenshot -o
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing value"* ]]
}

@test "screenshot_preview.sh rejects malformed --size" {
  run_screenshot --url http://localhost:1234 --size 1600
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --size"* ]]
}

@test "screenshot_preview.sh rejects non-numeric --wait" {
  run_screenshot --url http://localhost:1234 --wait fast
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --wait"* ]]
}

@test "list_previews.sh --help prints usage" {
  run_list --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"@Preview"* ]]
}

@test "list_previews.sh exits 1 if root does not exist" {
  run_list "$TEST_TMP/nope"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not a directory"* ]]
}
