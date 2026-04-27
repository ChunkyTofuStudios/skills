#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# CONFIG / INPUT
############################################

usage() {
  cat <<EOF
Usage: $0 [--stop] [--timeout <seconds>]

Launches \`flutter widget-preview start\` in the background and prints the
preview URL on stdout. Idempotent: re-running while a server is already
up just re-prints the existing URL.

Flags:
  --stop                 Tear down the server recorded in the state file
                         (kill the process, remove state) and exit.
  --timeout <seconds>    How long to wait for the URL to appear in the
                         preview server's log. Default: 60.
  -h, --help             Show this help.

Env:
  FLUTTER_BIN                Override the Flutter command (e.g. "fvm flutter",
                             "/path/to/flutter"). Default: auto-detect.
  PREVIEW_WIDGET_STATE_DIR   Where to keep the per-project state JSON + log.
                             Default: \$PWD/.preview-widget

State file (\$PREVIEW_WIDGET_STATE_DIR/server.json) shape:
  { "url": "http://localhost:51530",
    "pid": 12345,
    "log": "/abs/path/to/flutter-widget-preview.log",
    "started_at": "2026-04-27T12:34:56Z" }

Exit codes:
  0    Server is up; URL printed on stdout.
  1    Failed to start, or --stop ran but state was missing/invalid.
  127  Flutter not found.
EOF
}

############################################
# LOGGING
############################################

log()   { echo "[INFO] $*" >&2; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

############################################
# ARG PARSING
############################################

STOP=0
TIMEOUT=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --stop) STOP=1; shift ;;
    --timeout)
      [[ $# -ge 2 ]] || { error "Missing value for --timeout"; usage; exit 1; }
      TIMEOUT="$2"
      shift 2
      ;;
    *) error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

############################################
# STATE LOCATION
############################################

STATE_DIR="${PREVIEW_WIDGET_STATE_DIR:-$PWD/.preview-widget}"
STATE_FILE="$STATE_DIR/server.json"
LOG_FILE="$STATE_DIR/flutter-widget-preview.log"

############################################
# STATE HELPERS
############################################

# Read a top-level string field from the state JSON without depending on `jq`.
# Bash 3.2-compatible: matches `"key": "value"` (with optional whitespace) on
# any line and prints just the value.
read_state_string() {
  local key="$1" file="$2"
  awk -v k="$key" '
    BEGIN { pat = "\"" k "\"[[:space:]]*:[[:space:]]*\"" }
    {
      i = index($0, pat)
      if (i > 0) {
        s = substr($0, i + length(pat))
        j = index(s, "\"")
        if (j > 0) { print substr(s, 1, j - 1); exit }
      }
    }
  ' "$file"
}

read_state_number() {
  local key="$1" file="$2"
  awk -v k="$key" '
    BEGIN { pat = "\"" k "\"[[:space:]]*:[[:space:]]*" }
    {
      i = index($0, pat)
      if (i > 0) {
        s = substr($0, i + length(pat))
        # Strip a trailing comma or closing brace.
        gsub(/[,}].*$/, "", s)
        gsub(/[[:space:]]+/, "", s)
        print s; exit
      }
    }
  ' "$file"
}

# Return 0 if the recorded PID looks alive (and is still a flutter process).
state_pid_alive() {
  local pid
  pid=$(read_state_number pid "$STATE_FILE" 2>/dev/null || true)
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

############################################
# --STOP
############################################

if (( STOP == 1 )); then
  if [[ ! -f "$STATE_FILE" ]]; then
    log "No state file at $STATE_FILE; nothing to stop."
    exit 0
  fi

  pid=$(read_state_number pid "$STATE_FILE" 2>/dev/null || true)

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    log "Stopping preview server (pid $pid)..."
    kill "$pid" 2>/dev/null || true
    # Give it a moment to exit cleanly, then SIGKILL if needed.
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      warn "Process $pid did not exit on SIGTERM; sending SIGKILL."
      kill -9 "$pid" 2>/dev/null || true
    fi
  else
    log "Recorded pid is not alive; cleaning up state only."
  fi

  rm -f "$STATE_FILE"
  exit 0
fi

############################################
# IDEMPOTENT: SERVER ALREADY UP
############################################

if [[ -f "$STATE_FILE" ]] && state_pid_alive; then
  existing_url=$(read_state_string url "$STATE_FILE" 2>/dev/null || true)
  if [[ -n "$existing_url" ]]; then
    log "Reusing existing preview server."
    printf '%s\n' "$existing_url"
    exit 0
  fi
  warn "State file exists but URL is missing; restarting server."
fi

# Stale state (process died) → drop it and continue with a fresh launch.
if [[ -f "$STATE_FILE" ]]; then
  log "Found stale state file; clearing."
  rm -f "$STATE_FILE"
fi

############################################
# RESOLVE FLUTTER
############################################

declare -a FLUTTER_BIN_ARR=()

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  # shellcheck disable=SC2206  # intentional word-splitting
  FLUTTER_BIN_ARR=( $FLUTTER_BIN )
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN_ARR=( "flutter" )
elif command -v fvm >/dev/null 2>&1; then
  FLUTTER_BIN_ARR=( "fvm" "flutter" )
else
  error "Flutter not found. Install Flutter or set FLUTTER_BIN."
  exit 127
fi

############################################
# LAUNCH
############################################

mkdir -p "$STATE_DIR"
: > "$LOG_FILE"

log "Starting preview server: ${FLUTTER_BIN_ARR[*]} widget-preview start"

# `nohup` ignores SIGHUP so the bg process survives this script's exit.
# `</dev/null` so the child can't accidentally read our (already-closed) stdin.
# `disown` removes it from the shell's job table; harmless if it errors.
nohup "${FLUTTER_BIN_ARR[@]}" widget-preview start >"$LOG_FILE" 2>&1 </dev/null &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null || true

############################################
# WAIT FOR URL
############################################

URL=""
elapsed=0
poll_interval=1

while (( elapsed < TIMEOUT )); do
  # Match http(s)://localhost:PORT or http(s)://127.0.0.1:PORT. Tightening to
  # the loopback hosts avoids latching onto a docs URL the CLI might print
  # in its banner.
  URL=$(grep -oE 'https?://(localhost|127\.0\.0\.1):[0-9]+' "$LOG_FILE" 2>/dev/null \
    | head -n 1 || true)
  if [[ -n "$URL" ]]; then
    break
  fi

  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    error "flutter widget-preview start exited before printing a URL."
    error "Last 20 lines of $LOG_FILE:"
    tail -n 20 "$LOG_FILE" >&2 || true
    exit 1
  fi

  sleep "$poll_interval"
  elapsed=$(( elapsed + poll_interval ))
done

if [[ -z "$URL" ]]; then
  error "Timed out after ${TIMEOUT}s waiting for a preview URL."
  error "Last 20 lines of $LOG_FILE:"
  tail -n 20 "$LOG_FILE" >&2 || true
  # Best-effort cleanup so we don't leak the process.
  kill "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

############################################
# WRITE STATE
############################################

STARTED_AT=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Hand-rolled JSON keeps the script jq-free. URL/log are paths we control, so
# escaping is a non-issue; if that ever changes, switch to printf %q + jq.
cat > "$STATE_FILE" <<EOF
{
  "url": "$URL",
  "pid": $SERVER_PID,
  "log": "$LOG_FILE",
  "started_at": "$STARTED_AT"
}
EOF

log "Preview server up at $URL (pid $SERVER_PID)"
printf '%s\n' "$URL"
