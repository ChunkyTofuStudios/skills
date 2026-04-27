#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# CONFIG / INPUT
############################################

usage() {
  cat <<EOF
Usage: $0 <inputs...> [-o output] [--json]

Pass the stacktrace and 1 or 2 symbol inputs in any order:
  - Play Console stacktrace log (.txt/.log)
  - AppName_artifacts.zip or extracted dir (contains *.symbols)
  - android_native_debug_symbols.zip or extracted dir (contains ABI/*.so)

Flags:
  -o, --output <path>   Output file (default: <trace>.symbolized.txt next to the input).
  -j, --json            Emit a JSON summary on stdout instead of the text summary.
                        Shape: {"frames", "unresolved", "abi", "output"}

Examples:
  $0 stacktrace.txt AppName_artifacts.zip
  $0 android_native_debug_symbols.zip stacktrace.txt
  $0 android_native_debug_symbols.zip AppName_artifacts.zip stacktrace.txt --json
  $0 AppName_artifacts.zip stacktrace.txt -o symbolized.txt
EOF
}

############################################
# LOGGING
############################################

log()   { echo "[INFO] $*"; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

############################################
# ZIP EXTRACTION
############################################

_TMP_DIRS=()
cleanup() { [[ ${#_TMP_DIRS[@]} -eq 0 ]] || rm -rf "${_TMP_DIRS[@]}"; }
trap cleanup EXIT

maybe_extract() {
  local input="$1"
  if [[ -d "$input" ]]; then
    echo "$input"
  elif [[ -f "$input" && "$input" == *.zip ]]; then
    local tmp
    tmp=$(mktemp -d)
    _TMP_DIRS+=("$tmp")
    log "Extracting $(basename "$input")..." >&2
    unzip -q "$input" -d "$tmp"
    echo "$tmp"
  else
    error "Not a directory or .zip file: $input" >&2
    exit 1
  fi
}

contains_flutter_symbols() {
  local dir="$1"
  local match
  match=$(find "$dir" -name "*.symbols" -print -quit 2>/dev/null || true)
  [[ -n "$match" ]]
}

contains_native_symbols() {
  local dir="$1"
  local match
  match=$(find "$dir" \( \
    -path "*/arm64-v8a/*.so" -o \
    -path "*/armeabi-v7a/*.so" -o \
    -path "*/x86/*.so" -o \
    -path "*/x86_64/*.so" \
  \) -print -quit 2>/dev/null || true)
  [[ -n "$match" ]]
}

is_trace_file() {
  local input="$1"

  [[ -f "$input" ]] || return 1
  [[ "$input" == *.zip ]] && return 1

  grep -Eq \
    '(^# Crashlytics - Stack trace|^# Application:|^# Platform:|^# Issue:|pc 0x[0-9a-fA-F]+)' \
    "$input" 2>/dev/null
}

OUT_FILE=""
OUT_FILE_EXPLICIT=0
JSON_OUTPUT=0
declare -a POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o|--output)
      [[ $# -ge 2 ]] || { error "Missing value for $1"; usage; exit 1; }
      OUT_FILE="$2"
      OUT_FILE_EXPLICIT=1
      shift 2
      ;;
    -j|--json)
      JSON_OUTPUT=1
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL_ARGS+=("$1")
        shift
      done
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -lt 2 ]]; then
  usage
  exit 1
fi

TRACE_FILE=""
declare -a BUILD_DIRS=()
declare -a NATIVE_DIRS=()
declare -a UNKNOWN_ARGS=()

for arg in "${POSITIONAL_ARGS[@]}"; do
  if is_trace_file "$arg"; then
    if [[ -n "$TRACE_FILE" ]]; then
      error "Multiple stacktrace files detected: $TRACE_FILE and $arg"
      exit 1
    fi
    TRACE_FILE="$arg"
    log "Detected stacktrace: $arg"
    continue
  fi

  if [[ -d "$arg" || ( -f "$arg" && "$arg" == *.zip ) ]]; then
    extracted_dir=$(maybe_extract "$arg")
    matched=0

    if contains_flutter_symbols "$extracted_dir"; then
      BUILD_DIRS+=("$extracted_dir")
      matched=1
      log "Detected Flutter symbols: $arg"
    fi

    if contains_native_symbols "$extracted_dir"; then
      NATIVE_DIRS+=("$extracted_dir")
      matched=1
      log "Detected native debug symbols: $arg"
    fi

    if (( matched == 1 )); then
      continue
    fi
  fi

  UNKNOWN_ARGS+=("$arg")
done

if [[ ${#UNKNOWN_ARGS[@]} -gt 1 ]]; then
  error "Could not classify inputs: ${UNKNOWN_ARGS[*]}"
  usage
  exit 1
fi

if [[ ${#UNKNOWN_ARGS[@]} -eq 1 ]]; then
  classified_roles=0
  [[ -n "$TRACE_FILE" ]] && ((classified_roles += 1))
  [[ ${#BUILD_DIRS[@]} -gt 0 ]] && ((classified_roles += 1))
  [[ ${#NATIVE_DIRS[@]} -gt 0 ]] && ((classified_roles += 1))

  last_positional_index=$((${#POSITIONAL_ARGS[@]} - 1))
  last_positional="${POSITIONAL_ARGS[$last_positional_index]}"

  if (( OUT_FILE_EXPLICIT == 0 )) && (( classified_roles >= 2 )) && [[ "${UNKNOWN_ARGS[0]}" == "$last_positional" ]]; then
    OUT_FILE="${UNKNOWN_ARGS[0]}"
  else
    error "Could not classify input: ${UNKNOWN_ARGS[0]}"
    usage
    exit 1
  fi
fi

############################################
# VALIDATION
############################################

[[ -n "$TRACE_FILE" ]] || {
  error "No stacktrace file detected. Provide the Play Console stacktrace log plus at least one symbol input."
  exit 1
}

if [[ ${#BUILD_DIRS[@]} -eq 0 && ${#NATIVE_DIRS[@]} -eq 0 ]]; then
  error "No symbol inputs detected. Provide AppName_artifacts.zip and/or android_native_debug_symbols.zip."
  exit 1
fi

# Default output: <trace>.symbolized.txt next to the input trace, so the script
# never silently writes to CWD.
if [[ -z "$OUT_FILE" ]]; then
  trace_dir=$(dirname "$TRACE_FILE")
  trace_base=$(basename "$TRACE_FILE")
  OUT_FILE="${trace_dir}/${trace_base%.*}.symbolized.txt"
fi

############################################
# NDK / ADDR2LINE
############################################

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/27.3.13750724"
  log "Using default NDK: $ANDROID_NDK_HOME"
fi

# `|| true` lets the missing-NDK case surface as a clear "llvm-addr2line not
# found" below instead of `set -e` killing the script silently when find fails.
HOST_TAG=$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort | head -n 1 || true)
NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin"
A2L="$NDK_BIN/llvm-addr2line"

[[ -f "$A2L" ]] || { error "llvm-addr2line not found at $A2L (set ANDROID_NDK_HOME or install the NDK)"; exit 1; }

log "Using addr2line: $A2L"

# Prefer the NDK's llvm-readelf, fall back to whatever's on PATH.
# macOS doesn't ship `readelf` natively, so the NDK copy is the reliable one.
if [[ -f "$NDK_BIN/llvm-readelf" ]]; then
  READELF="$NDK_BIN/llvm-readelf"
else
  READELF=$(command -v llvm-readelf || command -v readelf || true)
fi

if [[ -n "$READELF" ]]; then
  log "Using readelf: $READELF"
else
  warn "No readelf found; Build-ID indexing skipped (symbolization still works, just slower)."
fi

############################################
# ABI DETECTION
############################################

ABI="arm64-v8a"

if grep -q "arm64" "$TRACE_FILE"; then ABI="arm64-v8a"; fi
if grep -q "armeabi" "$TRACE_FILE"; then ABI="armeabi-v7a"; fi
if grep -q "x86_64" "$TRACE_FILE"; then ABI="x86_64"; fi
if grep -q "x86[^_]" "$TRACE_FILE"; then ABI="x86"; fi

log "Detected ABI: $ABI"

############################################
# COLLECT SYMBOL FILES
############################################

declare -a SYMBOL_FILES=()

# Flutter split debug symbols
if [[ ${#BUILD_DIRS[@]} -gt 0 ]]; then
  for build_dir in "${BUILD_DIRS[@]}"; do
    while IFS= read -r -d '' f; do
      SYMBOL_FILES+=("$f")
    done < <(find "$build_dir" -name "*.symbols" -print0)
  done
fi

# Native debug symbols (ABI specific)
if [[ ${#NATIVE_DIRS[@]} -gt 0 ]]; then
  for native_dir in "${NATIVE_DIRS[@]}"; do
    while IFS= read -r -d '' f; do
      SYMBOL_FILES+=("$f")
    done < <(find "$native_dir" -path "*/$ABI/*.so" -print0)
  done
fi

if [[ ${#SYMBOL_FILES[@]} -eq 0 ]]; then
  error "No symbol files found for ABI $ABI"
  exit 1
fi

log "Loaded ${#SYMBOL_FILES[@]} symbol files"

############################################
# BUILD ID INDEXING (CRITICAL)
############################################

declare -a FILE_BUILD_ID_KEYS=()
declare -a FILE_BUILD_ID_VALS=()

if [[ -n "$READELF" ]]; then
  log "Indexing Build IDs..."

  for f in "${SYMBOL_FILES[@]}"; do
    build_id=$("$READELF" --notes "$f" 2>/dev/null | grep -i "Build ID" | awk '{print $3}' || true)
    if [[ -n "$build_id" ]]; then
      FILE_BUILD_ID_KEYS+=("$f")
      FILE_BUILD_ID_VALS+=("$build_id")
    fi
  done
fi

############################################
# SYMBOLIZATION CORE
############################################

symbolize_pc() {
  local pc="$1"
  local build_id_hint="$2"

  # Try matching Build ID first
  local i
  for i in "${!FILE_BUILD_ID_KEYS[@]}"; do
    if [[ "${FILE_BUILD_ID_VALS[$i]}" == "$build_id_hint" ]]; then
      try_symbolize "$pc" "${FILE_BUILD_ID_KEYS[$i]}" && return 0
    fi
  done

  # Fallback: try everything
  for f in "${SYMBOL_FILES[@]}"; do
    try_symbolize "$pc" "$f" && return 0
  done

  return 1
}

try_symbolize() {
  local pc="$1"
  local file="$2"

  local out
  out=$("$A2L" -a -f -C -i -e "$file" "$pc" 2>/dev/null || true)

  local first
  first=$(echo "$out" | awk 'NF{print; exit}')

  if [[ -n "$first" && "$first" != "??" && "$first" != "??:0" ]]; then
    echo "$file|$out"
    return 0
  fi

  return 1
}

############################################
# PROCESS TRACE
############################################

: > "$OUT_FILE"

log "Symbolizing..."

UNRESOLVED=0
TOTAL=0

while IFS= read -r line; do
  if [[ "$line" =~ pc\ (0x[0-9a-fA-F]+) ]]; then
    ((++TOTAL))

    pc="${BASH_REMATCH[1]}"
    build_id=$(echo "$line" | grep -oE 'BuildId: [0-9a-f]+' | awk '{print $2}' || true)

    echo "$line" >> "$OUT_FILE"

    if result=$(symbolize_pc "$pc" "$build_id"); then
      file="${result%%|*}"
      text="${result#*|}"

      echo "    -> $file" >> "$OUT_FILE"
      echo "$text" >> "$OUT_FILE"
    else
      echo "    -> [UNRESOLVED]" >> "$OUT_FILE"
      ((++UNRESOLVED))
    fi
  else
    echo "$line" >> "$OUT_FILE"
  fi
done < "$TRACE_FILE"

############################################
# SUMMARY
############################################

log "Done → $OUT_FILE"

if (( JSON_OUTPUT == 1 )); then
  # All UI/status went to stderr; stdout is exactly one JSON object.
  printf '{"frames":%d,"unresolved":%d,"abi":"%s","output":"%s"}\n' \
    "$TOTAL" "$UNRESOLVED" "$ABI" "$OUT_FILE"
else
  echo ""
  echo "========== SUMMARY =========="
  echo "Frames: $TOTAL"
  echo "Unresolved: $UNRESOLVED"

  if (( UNRESOLVED > 0 )); then
    warn "Some frames unresolved."

    echo ""
    echo "Possible causes:"
    echo "- Missing symbols for one of the Build IDs"
    echo "- Wrong build artifacts (common)"
    echo "- Flutter AOT optimization removed symbols"
  fi
fi
