#!/usr/bin/env bats
# Tests for help / arg-validation behavior.

load helpers

setup()    { sym_setup; }
teardown() { sym_teardown; }

@test "--help prints usage" {
  run_sym --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"<inputs...>"* ]]
}

@test "-h prints usage" {
  run_sym -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "no args prints usage and exits 1" {
  run_sym
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "single arg prints usage and exits 1" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-o without a value errors out" {
  run_sym -o
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing value"* ]]
}
