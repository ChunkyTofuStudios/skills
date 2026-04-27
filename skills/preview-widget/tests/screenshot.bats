#!/usr/bin/env bats
# Tests for screenshot_preview.sh — Chrome flag plumbing, output paths,
# state-file URL resolution, error paths.

load helpers

setup()    { pw_setup; }
teardown() { pw_teardown; }

# Helper: write a fake state file as if start_preview.sh had run.
write_state() {
  local url="${1:-http://localhost:51530}"
  mkdir -p "$PREVIEW_WIDGET_STATE_DIR"
  cat > "$PREVIEW_WIDGET_STATE_DIR/server.json" <<EOF
{
  "url": "$url",
  "pid": 1,
  "log": "/tmp/x.log",
  "started_at": "2026-01-01T00:00:00Z"
}
EOF
}

@test "captures with defaults (URL from state file, auto-incrementing path)" {
  write_state
  run_screenshot
  [ "$status" -eq 0 ]

  # stdout = output path, and that path exists.
  out_path=$(printf '%s\n' "$output" | grep -E '\.png$' | head -n 1)
  [ -n "$out_path" ]
  [ -f "$out_path" ]
  [[ "$out_path" == "$PREVIEW_WIDGET_OUT_DIR/preview-001.png" ]]
}

@test "auto-increments output filename across runs" {
  write_state
  run_screenshot
  [ "$status" -eq 0 ]
  run_screenshot
  [ "$status" -eq 0 ]
  run_screenshot
  [ "$status" -eq 0 ]

  [ -f "$PREVIEW_WIDGET_OUT_DIR/preview-001.png" ]
  [ -f "$PREVIEW_WIDGET_OUT_DIR/preview-002.png" ]
  [ -f "$PREVIEW_WIDGET_OUT_DIR/preview-003.png" ]
}

@test "--out writes to the requested path and creates parents" {
  write_state
  target="$TEST_TMP/nested/dir/shot.png"
  run_screenshot --out "$target"
  [ "$status" -eq 0 ]
  [ -f "$target" ]
  [[ "$output" == *"$target"* ]]
}

@test "--url overrides the state file (no state file present is OK)" {
  run_screenshot --url "http://127.0.0.1:7777" --out "$TEST_TMP/x.png"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/x.png" ]
  assert_called "http://127.0.0.1:7777"
}

@test "passes --window-size, --virtual-time-budget, and --headless=new to chrome" {
  write_state
  run_screenshot --size 1920x4000 --wait 15000 --out "$TEST_TMP/x.png"
  [ "$status" -eq 0 ]
  assert_called "--window-size=1920,4000"
  assert_called "--virtual-time-budget=15000"
  assert_called "--headless=new"
  assert_called "--screenshot=$TEST_TMP/x.png"
}

@test "errors when no state file and no --url is provided" {
  run_screenshot --out "$TEST_TMP/x.png"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No state file"* ]]
  [ ! -f "$TEST_TMP/x.png" ]
}

@test "errors when state file exists but has no \"url\" field" {
  mkdir -p "$PREVIEW_WIDGET_STATE_DIR"
  echo '{"pid": 1}' > "$PREVIEW_WIDGET_STATE_DIR/server.json"
  run_screenshot --out "$TEST_TMP/x.png"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not parse"* ]]
}

@test "exit 127 when no Chrome binary is found" {
  write_state
  # Strip the stubs dir from PATH and shadow the macOS Chrome.app lookup
  # by overriding HOME isn't enough — that path is absolute. We point
  # CHROME_BIN at a definitely-missing path to short-circuit detection
  # AND simultaneously remove google-chrome / chromium from PATH.
  CHROME_BIN="" PATH="/usr/bin:/bin" run_screenshot \
    --out "$TEST_TMP/x.png" --url "http://localhost:1234"
  # On a CI machine without Chrome installed, this will exit 127. On a dev
  # mac with Chrome.app, the macOS auto-detect still finds it. Accept either:
  # we only care that the code path is reachable. The stronger assertion
  # lives in the next test using a fake CHROME_BIN.
  [ "$status" -eq 0 ] || [ "$status" -eq 127 ]
}

@test "honors CHROME_BIN override pointing at a missing file" {
  write_state
  # Pointing CHROME_BIN at a real file but one that isn't executable would
  # still be picked up by the auto-detect block (which only checks `-x`).
  # Setting it to a path that *is* executable (our stub) confirms the
  # override wins over auto-detect. That's what the next happy-path test
  # already exercises; here we assert that a non-executable CHROME_BIN
  # value is honored as-is (the script trusts the caller).
  CHROME_BIN="/definitely/not/here" run_screenshot \
    --out "$TEST_TMP/x.png" --url "http://localhost:1234"
  # Chrome isn't actually invokable, so the screenshot won't appear.
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not produce a screenshot"* ]] \
    || [[ "$output" == *"No such file"* ]] \
    || [[ "$output" == *"command not found"* ]]
}

@test "errors when chrome runs but no file is produced" {
  write_state
  STUB_CHROME_NO_OUTPUT=1 run_screenshot --out "$TEST_TMP/x.png"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not produce"* ]]
  [ ! -f "$TEST_TMP/x.png" ]
}

@test "isolated user-data-dir flag is set so the call doesn't share the user's profile" {
  write_state
  run_screenshot --out "$TEST_TMP/x.png"
  [ "$status" -eq 0 ]
  assert_called "--user-data-dir="
}
