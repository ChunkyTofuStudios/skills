#!/usr/bin/env bats
# Tests that the script correctly classifies its positional inputs as the
# stacktrace, the Flutter-symbols dir/zip, the native-symbols dir/zip, or
# (when ambiguous) the output file.

load helpers

setup()    { sym_setup; }
teardown() { sym_teardown; }

# ---------------------------------------------------------------------------
# Trace recognition
# ---------------------------------------------------------------------------

@test "Crashlytics-style trace is recognized" {
  trace=$(stage_trace crashlytics-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected stacktrace: $trace"* ]]
}

@test "Play Console ANR-style trace is recognized via pc 0x lines" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected stacktrace: $trace"* ]]
}

@test "passing two trace files errors out" {
  t1=$(stage_trace play-anr-trace.log)
  cp "$SYM_FIXTURES_DIR/crashlytics-trace.log" "$TEST_TMP/second.log"
  run_sym "$t1" "$TEST_TMP/second.log" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Multiple stacktrace files"* ]]
}

@test "no trace file among inputs errors out" {
  run_sym "$SYM_FIXTURES_DIR/symbols" "$SYM_FIXTURES_DIR/flutter"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No stacktrace file detected"* ]]
}

# ---------------------------------------------------------------------------
# Symbol input recognition
# ---------------------------------------------------------------------------

@test "ABI-shaped directory is classified as native debug symbols" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected native debug symbols"* ]]
}

@test "directory with .symbols files is classified as Flutter symbols" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols" "$SYM_FIXTURES_DIR/flutter"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected Flutter symbols"* ]]
}

@test "argument order is irrelevant — symbols first, trace last works" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$SYM_FIXTURES_DIR/symbols" "$trace"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected stacktrace"* ]]
  [[ "$output" == *"Detected native debug symbols"* ]]
}

# ---------------------------------------------------------------------------
# Output-path classification
# ---------------------------------------------------------------------------

@test "trailing unclassified arg becomes the output file when 2 roles are filled" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols" "$TEST_TMP/custom-out.txt"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/custom-out.txt" ]
}

@test "non-trailing unclassified arg is rejected" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$TEST_TMP/orphan.txt" "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not classify"* ]]
}

# ---------------------------------------------------------------------------
# Default output path
# ---------------------------------------------------------------------------

@test "default output file is <trace>.symbolized.txt next to the trace" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/play-anr-trace.symbolized.txt" ]
}
