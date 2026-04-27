#!/usr/bin/env bats
# End-to-end tests for the symbolization loop with stubbed addr2line/readelf.

load helpers

setup()    { sym_setup; }
teardown() { sym_teardown; }

@test "ABI is detected as arm64-v8a from a trace mentioning split_config.arm64_v8a.apk" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected ABI: arm64-v8a"* ]]
}

@test "frames whose Build ID matches the trace get resolved via addr2line" {
  trace=$(stage_trace play-anr-trace.log)

  export STUB_READELF_BUILD_ID="libapp.so=deadbeefcafef00d1234567890abcdef00000001"
  # Stub format: '|' inside the value is rewritten to a newline by the stub,
  # so the multi-line addr2line reply (function then file:line) stays a
  # single env-var line.
  export STUB_A2L_RESPONSES="libapp.so:0x00000000004c9534=foo(int)|libapp/foo.cc:42"

  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]

  out="$TEST_TMP/play-anr-trace.symbolized.txt"
  [ -f "$out" ]
  grep -q 'foo(int)' "$out"
  grep -q 'libapp/foo.cc:42' "$out"
}

@test "frames addr2line cannot resolve are marked [UNRESOLVED:…]" {
  trace=$(stage_trace play-anr-trace.log)
  # No STUB_A2L_RESPONSES → every PC returns ?? / ??:0.
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]

  out="$TEST_TMP/play-anr-trace.symbolized.txt"
  grep -q '\[UNRESOLVED:' "$out"
}

@test "frames with no BuildId are labeled [SYSTEM]" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]

  out="$TEST_TMP/play-anr-trace.symbolized.txt"
  # The fixture's frame #00 is `/apex/.../libc.so` with no BuildId.
  grep -q '\[SYSTEM:' "$out"
}

@test "summary reports resolved/unresolved/system breakdown" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]
  # Fixture has 3 native frames: 1 system + 2 with a BuildId that the default
  # readelf stub doesn't recognize → 2 unresolved.
  [[ "$output" == *"Frames: 3"* ]]
  [[ "$output" == *"Unresolved: 2"* ]]
  [[ "$output" == *"System / external: 1"* ]]
}

@test "frames from Google system packages with BuildIds are labeled [SYSTEM]" {
  trace=$(stage_trace play-anr-trace-system-buildid.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -eq 0 ]

  out="$TEST_TMP/play-anr-trace-system-buildid.symbolized.txt"
  # Two system frames (gms + webview) — both get [SYSTEM:.
  [ "$(grep -c '\[SYSTEM:' "$out")" -eq 2 ]
  # The user-app frame still goes through normal BuildId handling — readelf
  # stub gives nothing for `libapp.so` here, so it's [UNRESOLVED:.
  [ "$(grep -c '\[UNRESOLVED:' "$out")" -eq 1 ]
  # And critically: the system BuildIds must NOT show up in the
  # "no matching symbol file" warning section. Frame *trace lines* go to the
  # output file only, so $output is the SUMMARY block + log lines.
  [[ "$output" != *"a2d39cc045dd41131e53ed60dc7ddca2"* ]]
  [[ "$output" != *"c0d75ff5364ef82cbfefff89b96c07c57b4fdda3"* ]]
  # The user-app BuildId (deadbeef…) is genuinely unmatched and should be
  # listed.
  [[ "$output" == *"deadbeefcafef00d1234567890abcdef00000001"* ]]
}

@test "--json emits a parseable summary on stdout" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols" --json
  [ "$status" -eq 0 ]

  # Stderr lines (status logs) should not bleed into stdout. With `run`, both
  # streams are merged into $output, so we look for the JSON object directly.
  json_line=$(printf '%s\n' "$output" | grep -E '^\{.*"frames":')
  [ -n "$json_line" ]
  echo "$json_line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['frames'] == 3 and d['abi'] == 'arm64-v8a' and 'output' in d"
}

@test "-o overrides the output path" {
  trace=$(stage_trace play-anr-trace.log)
  run_sym "$trace" "$SYM_FIXTURES_DIR/symbols" -o "$TEST_TMP/explicit.txt"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/explicit.txt" ]
  [ ! -f "$TEST_TMP/play-anr-trace.symbolized.txt" ]
}

@test "fails fast if NDK is missing addr2line" {
  trace=$(stage_trace play-anr-trace.log)
  ANDROID_NDK_HOME="$TEST_TMP/nonexistent-ndk" run_sym "$trace" "$SYM_FIXTURES_DIR/symbols"
  [ "$status" -ne 0 ]
  [[ "$output" == *"llvm-addr2line not found"* ]]
}
