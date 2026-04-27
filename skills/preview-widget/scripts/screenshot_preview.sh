#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# CONFIG / INPUT
############################################

usage() {
  cat <<EOF
Usage: $0 [--out <path>] [--size WxH] [--wait <ms>] [--url <url>]

Captures a headless-Chrome screenshot of the Flutter Widget Previewer
running on localhost. Prints the absolute output path on stdout.

Flags:
  -o, --out <path>     Output PNG path. Default: \$PREVIEW_WIDGET_OUT_DIR/preview-NNN.png
                       (auto-incrementing; default dir is /tmp/preview-widget).
  -s, --size <WxH>     Chrome viewport in pixels. Default: 1600x2400. Taller
                       captures more stacked preview tiles in one shot.
  -w, --wait <ms>      Virtual-time budget Chrome waits before snapping, in
                       milliseconds. Default: 10000. Bump if the first paint
                       is blank (the Flutter web canvas needs time to bootstrap).
  -u, --url <url>      Override the URL. Default: read from the state file
                       written by start_preview.sh.
  -h, --help           Show this help.

Env:
  CHROME_BIN                  Override the Chrome/Chromium binary.
                              Default: auto-detect macOS Chrome.app, then
                              google-chrome / chromium / chromium-browser on PATH.
  PREVIEW_WIDGET_STATE_DIR    Where to read server.json from. Default: \$PWD/.preview-widget
  PREVIEW_WIDGET_OUT_DIR      Default output directory. Default: /tmp/preview-widget

Exit codes:
  0    Screenshot written; path printed on stdout.
  1    No URL available, or Chrome did not produce a file.
  127  No Chrome/Chromium binary found.
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

OUT=""
SIZE="1600x2400"
WAIT_MS="10000"
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -o|--out)
      [[ $# -ge 2 ]] || { error "Missing value for $1"; usage; exit 1; }
      OUT="$2"; shift 2 ;;
    -s|--size)
      [[ $# -ge 2 ]] || { error "Missing value for $1"; usage; exit 1; }
      SIZE="$2"; shift 2 ;;
    -w|--wait)
      [[ $# -ge 2 ]] || { error "Missing value for $1"; usage; exit 1; }
      WAIT_MS="$2"; shift 2 ;;
    -u|--url)
      [[ $# -ge 2 ]] || { error "Missing value for $1"; usage; exit 1; }
      URL="$2"; shift 2 ;;
    *) error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

############################################
# VALIDATE SIZE / WAIT
############################################

if [[ ! "$SIZE" =~ ^[0-9]+x[0-9]+$ ]]; then
  error "Invalid --size '$SIZE'. Expected WxH (e.g. 1600x2400)."
  exit 1
fi
W="${SIZE%x*}"
H="${SIZE#*x}"

if [[ ! "$WAIT_MS" =~ ^[0-9]+$ ]]; then
  error "Invalid --wait '$WAIT_MS'. Expected milliseconds (positive integer)."
  exit 1
fi

############################################
# RESOLVE URL
############################################

if [[ -z "$URL" ]]; then
  STATE_DIR="${PREVIEW_WIDGET_STATE_DIR:-$PWD/.preview-widget}"
  STATE_FILE="$STATE_DIR/server.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    error "No state file at $STATE_FILE."
    error "Run scripts/start_preview.sh first, or pass --url <url>."
    exit 1
  fi
  URL=$(awk '
    {
      i = index($0, "\"url\"")
      if (i > 0) {
        s = substr($0, i)
        # Skip past the key, the colon, and the opening quote of the value.
        j = index(s, ":")
        if (j == 0) next
        s = substr(s, j + 1)
        k = index(s, "\"")
        if (k == 0) next
        s = substr(s, k + 1)
        l = index(s, "\"")
        if (l == 0) next
        print substr(s, 1, l - 1); exit
      }
    }
  ' "$STATE_FILE")
  if [[ -z "$URL" ]]; then
    error "Could not parse \"url\" out of $STATE_FILE."
    exit 1
  fi
fi

############################################
# RESOLVE CHROME
############################################

if [[ -z "${CHROME_BIN:-}" ]]; then
  if [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
    CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  elif [[ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]]; then
    CHROME_BIN="/Applications/Chromium.app/Contents/MacOS/Chromium"
  elif command -v google-chrome >/dev/null 2>&1; then
    CHROME_BIN="google-chrome"
  elif command -v chromium >/dev/null 2>&1; then
    CHROME_BIN="chromium"
  elif command -v chromium-browser >/dev/null 2>&1; then
    CHROME_BIN="chromium-browser"
  else
    error "Chrome/Chromium not found. Install Chrome or set CHROME_BIN=/path/to/chrome."
    exit 127
  fi
fi

############################################
# RESOLVE OUTPUT PATH
############################################

if [[ -z "$OUT" ]]; then
  OUT_DIR="${PREVIEW_WIDGET_OUT_DIR:-/tmp/preview-widget}"
  mkdir -p "$OUT_DIR"
  # Auto-increment: preview-001.png, preview-002.png, ...
  n=1
  while :; do
    candidate=$(printf '%s/preview-%03d.png' "$OUT_DIR" "$n")
    if [[ ! -e "$candidate" ]]; then
      OUT="$candidate"
      break
    fi
    n=$(( n + 1 ))
    # Bail out at a sane upper bound rather than spinning forever.
    if (( n > 9999 )); then
      error "Output directory $OUT_DIR has too many existing screenshots; pass --out explicitly."
      exit 1
    fi
  done
fi

# Make sure the parent dir exists for explicit --out paths.
out_parent=$(dirname "$OUT")
mkdir -p "$out_parent"

############################################
# RUN CHROME
############################################

# Isolated profile dir prevents the headless run from clobbering or being
# clobbered by the user's regular Chrome session.
PROFILE_DIR=$(mktemp -d -t preview-widget-chrome-XXXXXX)
cleanup() {
  rm -rf "$PROFILE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

log "Capturing $URL → $OUT (${W}x${H}, wait ${WAIT_MS}ms)"

# `--headless=new` is the modern headless mode (Chrome 109+); it's noticeably
# more reliable than legacy `--headless`, especially for canvas/WebGL pages
# like the Flutter previewer. Older Chromes ignore the `=new` and fall back
# to legacy headless.
"$CHROME_BIN" \
  --headless=new \
  --hide-scrollbars \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --disable-extensions \
  --user-data-dir="$PROFILE_DIR" \
  --window-size="$W,$H" \
  --virtual-time-budget="$WAIT_MS" \
  --screenshot="$OUT" \
  "$URL" \
  >/dev/null 2>&1 || true

if [[ ! -f "$OUT" ]]; then
  error "Chrome did not produce a screenshot at $OUT."
  error "Try: bumping --wait, checking the URL is reachable, or running Chrome manually with the same flags."
  exit 1
fi

# stdout = the path, so the agent can `Read` it directly.
printf '%s\n' "$OUT"
