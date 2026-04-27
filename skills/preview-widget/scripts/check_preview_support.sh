#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# CONFIG / INPUT
############################################

usage() {
  cat <<EOF
Usage: $0 [--quiet]

Verifies that the Flutter on PATH (or via FLUTTER_BIN) is new enough to run
the Flutter Widget Previewer (\`flutter widget-preview start\`).

Requirements checked:
  - \`flutter\` (or \`fvm flutter\`) is callable.
  - Reported version >= 3.35.0 (the first release with widget-preview).

Flags:
  -q, --quiet  Print nothing on success; still exit non-zero on failure.
  -h, --help   Show this help.

Env:
  FLUTTER_BIN  Override the Flutter command (e.g. "fvm flutter",
               "/path/to/flutter"). Default: auto-detect.

Exit codes:
  0    Flutter is recent enough; ready to use widget previews.
  1    Flutter is older than 3.35; upgrade required.
  127  No Flutter binary found on PATH (and no FLUTTER_BIN).
EOF
}

############################################
# LOGGING
############################################

QUIET=0
log()   { (( QUIET == 1 )) || echo "[INFO] $*"; }
error() { echo "[ERROR] $*" >&2; }

############################################
# ARG PARSING
############################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -q|--quiet) QUIET=1; shift ;;
    *) error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

############################################
# RESOLVE FLUTTER
############################################

# FLUTTER_BIN may be a single path or a multi-word command (e.g. "fvm flutter").
# Split into an array so `"${FLUTTER_BIN_ARR[@]}" --version` works without
# spawning a subshell.
declare -a FLUTTER_BIN_ARR=()

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  # shellcheck disable=SC2206  # intentional word-splitting on FLUTTER_BIN
  FLUTTER_BIN_ARR=( $FLUTTER_BIN )
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN_ARR=( "flutter" )
elif command -v fvm >/dev/null 2>&1; then
  FLUTTER_BIN_ARR=( "fvm" "flutter" )
else
  error "Flutter not found. Install from https://docs.flutter.dev/get-started/install or set FLUTTER_BIN."
  exit 127
fi

############################################
# VERSION CHECK
############################################

# `flutter --version` first line looks like:
#   Flutter 3.38.0 • channel stable • https://github.com/flutter/flutter.git
# We only care about the second whitespace-delimited token.
raw_version_line=$( "${FLUTTER_BIN_ARR[@]}" --version 2>/dev/null | head -n 1 || true )

if [[ -z "$raw_version_line" ]]; then
  error "\`${FLUTTER_BIN_ARR[*]} --version\` produced no output. Is Flutter installed correctly?"
  exit 1
fi

version_token=$(printf '%s\n' "$raw_version_line" | awk '{print $2}')

if [[ -z "$version_token" ]]; then
  error "Could not parse a version token from: $raw_version_line"
  exit 1
fi

# Strip any trailing pre-release/build suffix (e.g. "3.38.0-1.2.pre" → "3.38.0").
version_clean=${version_token%%-*}

# Split on dots. Pad to 3 components so a hypothetical "3.35" still compares.
IFS='.' read -r major minor patch <<<"$version_clean"
major=${major:-0}
minor=${minor:-0}
patch=${patch:-0}

# Required minimum: 3.35.0
REQ_MAJOR=3
REQ_MINOR=35

if (( major < REQ_MAJOR )) || { (( major == REQ_MAJOR )) && (( minor < REQ_MINOR )); }; then
  error "Flutter $version_clean is too old for widget-preview (need >= ${REQ_MAJOR}.${REQ_MINOR}.0)."
  error "Upgrade with: ${FLUTTER_BIN_ARR[*]} upgrade"
  exit 1
fi

log "Flutter ${version_clean} (${FLUTTER_BIN_ARR[*]}) supports widget previews."
exit 0
