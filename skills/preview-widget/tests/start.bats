#!/usr/bin/env bats
# Tests for start_preview.sh — URL parsing, state file, idempotency, --stop.

load helpers

setup()    { pw_setup; }
teardown() { pw_teardown; }

@test "starts the server, captures URL, writes state file" {
  run_start --timeout 10
  [ "$status" -eq 0 ]

  # The URL is the only thing on stdout (modulo a trailing newline).
  url_line=$(printf '%s\n' "$output" | grep -E '^http://localhost:[0-9]+$' | head -n 1)
  [ -n "$url_line" ]
  [ "$url_line" = "http://localhost:51530" ]

  state_file="$PREVIEW_WIDGET_STATE_DIR/server.json"
  [ -f "$state_file" ]
  grep -q '"url"' "$state_file"
  grep -q '"pid"' "$state_file"
  grep -q '"log"' "$state_file"
  grep -q 'http://localhost:51530' "$state_file"

  # The recorded PID should be a live process (the stub flutter is still
  # sleeping in the background).
  pid=$(awk '/"pid"/ {gsub(/[^0-9]/, ""); print; exit}' "$state_file")
  [ -n "$pid" ]
  kill -0 "$pid" 2>/dev/null
}

@test "honors a custom URL from the stub" {
  STUB_FLUTTER_URL="http://127.0.0.1:62000" run_start --timeout 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"http://127.0.0.1:62000"* ]]
}

@test "is idempotent — second invocation reuses the running server" {
  run_start --timeout 10
  [ "$status" -eq 0 ]

  state_file="$PREVIEW_WIDGET_STATE_DIR/server.json"
  pid_first=$(awk '/"pid"/ {gsub(/[^0-9]/, ""); print; exit}' "$state_file")

  run_start --timeout 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"http://localhost:51530"* ]]

  pid_second=$(awk '/"pid"/ {gsub(/[^0-9]/, ""); print; exit}' "$state_file")
  [ "$pid_first" = "$pid_second" ]
}

@test "fails when flutter widget-preview start exits before printing a URL" {
  STUB_FLUTTER_PREVIEW_FAIL=1 run_start --timeout 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"exited before printing a URL"* ]]
  # No state file should be written on failure.
  [ ! -f "$PREVIEW_WIDGET_STATE_DIR/server.json" ]
}

@test "times out when no URL ever appears in the log" {
  STUB_FLUTTER_PREVIEW_NO_URL=1 STUB_FLUTTER_PREVIEW_LIFETIME=30 \
    run_start --timeout 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timed out"* ]]
}

@test "--stop on a missing state file is a no-op (exit 0)" {
  run_start --stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to stop"* ]]
}

@test "--stop kills the recorded PID and removes the state file" {
  run_start --timeout 10
  [ "$status" -eq 0 ]

  state_file="$PREVIEW_WIDGET_STATE_DIR/server.json"
  pid=$(awk '/"pid"/ {gsub(/[^0-9]/, ""); print; exit}' "$state_file")
  [ -n "$pid" ]
  kill -0 "$pid" 2>/dev/null

  run_start --stop
  [ "$status" -eq 0 ]
  [ ! -f "$state_file" ]
  # Process should be gone (give the kill a moment).
  ! kill -0 "$pid" 2>/dev/null
}

@test "stale state file (process gone) is replaced on next start" {
  mkdir -p "$PREVIEW_WIDGET_STATE_DIR"
  cat > "$PREVIEW_WIDGET_STATE_DIR/server.json" <<EOF
{
  "url": "http://localhost:9",
  "pid": 999999,
  "log": "/tmp/nonexistent.log",
  "started_at": "2020-01-01T00:00:00Z"
}
EOF

  run_start --timeout 10
  [ "$status" -eq 0 ]
  # New URL, not the stale one.
  [[ "$output" == *"http://localhost:51530"* ]]
  [[ "$output" != *"http://localhost:9"* ]]
}

@test "exit 127 when no flutter binary is on PATH and no FLUTTER_BIN" {
  # Drop the stubs dir from PATH so `flutter` disappears.
  PATH="/usr/bin:/bin" run_start --timeout 5
  [ "$status" -eq 127 ]
  [[ "$output" == *"Flutter not found"* ]]
}
