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

# Side-effect: sets `_LAST_SOURCE_LABEL` so the caller can render output paths
# rooted at the original archive (e.g. `Pixel_Buddy_31_artifacts.zip!build/...`)
# instead of the temp dir we delete on exit.
_LAST_SOURCE_LABEL=""
maybe_extract() {
  local input="$1"
  if [[ -d "$input" ]]; then
    _LAST_SOURCE_LABEL="$(basename "$input")/"
    echo "$input"
  elif [[ -f "$input" && "$input" == *.zip ]]; then
    local tmp
    tmp=$(mktemp -d)
    _TMP_DIRS+=("$tmp")
    log "Extracting $(basename "$input")..." >&2
    unzip -q "$input" -d "$tmp"
    _LAST_SOURCE_LABEL="$(basename "$input")!"
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
declare -a BUILD_SOURCES=()
declare -a NATIVE_DIRS=()
declare -a NATIVE_SOURCES=()
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
    source_label="$_LAST_SOURCE_LABEL"
    matched=0

    if contains_flutter_symbols "$extracted_dir"; then
      BUILD_DIRS+=("$extracted_dir")
      BUILD_SOURCES+=("$source_label")
      matched=1
      log "Detected Flutter symbols: $arg"
    fi

    if contains_native_symbols "$extracted_dir"; then
      NATIVE_DIRS+=("$extracted_dir")
      NATIVE_SOURCES+=("$source_label")
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

# Map detected ABI → expected Flutter `*.symbols` filename. Codemagic ships
# all three split-debug variants in the same artefact; loading the wrong-
# architecture file means addr2line will return spurious matches against
# whichever Dart snapshot range happens to overlap the PC.
case "$ABI" in
  arm64-v8a)   FLUTTER_SYM_NAME="app.android-arm64.symbols" ;;
  armeabi-v7a) FLUTTER_SYM_NAME="app.android-arm.symbols"   ;;
  x86_64)      FLUTTER_SYM_NAME="app.android-x64.symbols"   ;;
  x86)         FLUTTER_SYM_NAME="app.android-ia32.symbols"  ;;
  *)           FLUTTER_SYM_NAME=""                          ;;
esac

declare -a SYMBOL_FILES=()
declare -a SYMBOL_DISPLAY=()

# Flutter split debug symbols — only the file matching the detected ABI.
if [[ ${#BUILD_DIRS[@]} -gt 0 ]]; then
  for i in "${!BUILD_DIRS[@]}"; do
    build_dir="${BUILD_DIRS[$i]}"
    source_label="${BUILD_SOURCES[$i]}"
    while IFS= read -r -d '' f; do
      base=$(basename "$f")
      if [[ -n "$FLUTTER_SYM_NAME" && "$base" != "$FLUTTER_SYM_NAME" ]]; then
        continue
      fi
      SYMBOL_FILES+=("$f")
      SYMBOL_DISPLAY+=("${source_label}${f#"${build_dir}/"}")
    done < <(find "$build_dir" -name "*.symbols" -print0)
  done
fi

# Native debug symbols — already filtered by ABI via the find -path filter.
if [[ ${#NATIVE_DIRS[@]} -gt 0 ]]; then
  for i in "${!NATIVE_DIRS[@]}"; do
    native_dir="${NATIVE_DIRS[$i]}"
    source_label="${NATIVE_SOURCES[$i]}"
    while IFS= read -r -d '' f; do
      SYMBOL_FILES+=("$f")
      SYMBOL_DISPLAY+=("${source_label}${f#"${native_dir}/"}")
    done < <(find "$native_dir" -path "*/$ABI/*.so" -print0)
  done
fi

if [[ ${#SYMBOL_FILES[@]} -eq 0 ]]; then
  error "No symbol files found for ABI $ABI"
  exit 1
fi

log "Loaded ${#SYMBOL_FILES[@]} symbol file(s) for ABI $ABI"

############################################
# BUILD ID INDEXING (CRITICAL)
############################################

# We rely on Build IDs to pick the correct symbol file per frame. Without them
# every PC would have to be probed against every binary, and `addr2line` will
# happily return a hit for an unrelated address inside an AOT Dart snapshot —
# so a missing readelf is fatal here.
if [[ -z "$READELF" ]]; then
  error "llvm-readelf is required for Build ID matching. Install the Android NDK or set ANDROID_NDK_HOME."
  exit 1
fi

declare -a SYMBOL_BUILDIDS=()

log "Indexing Build IDs..."

for f in "${SYMBOL_FILES[@]}"; do
  # llvm-readelf emits two lines containing "Build ID":
  #   `  GNU  ...  NT_GNU_BUILD_ID (unique build ID bitstring)`
  #   `    Build ID: <hex>`
  # Anchor on the second one so we capture only the hex value. (The previous
  # `grep -i "Build ID" | awk '{print $3}'` captured both, producing a
  # multi-line value that never compared equal to a trace's Build ID.)
  build_id=$("$READELF" --notes "$f" 2>/dev/null \
    | awk '/^[[:space:]]*Build ID:/ { print tolower($3); exit }' || true)
  SYMBOL_BUILDIDS+=("$build_id")
done

############################################
# SYSTEM-FRAME CLASSIFIER
############################################

# Returns 0 (true) if the binary at $1 is from outside the user's build —
# Android runtime/system/vendor libs, or Google's system-installed APKs that
# carry their own Build IDs (Play Services, System WebView, Chrome, Trichrome).
# We can't and shouldn't try to resolve those against Codemagic artefacts, even
# when the trace gives us a Build ID for them.
is_system_path() {
  case "$1" in
    /apex/*|/system/*|/vendor/*) return 0 ;;
    /data/app/*/com.google.android.gms-*) return 0 ;;
    /data/app/*/com.google.android.webview-*) return 0 ;;
    /data/app/*/com.android.chrome-*) return 0 ;;
    /data/app/*/com.google.android.trichromelibrary*) return 0 ;;
  esac
  return 1
}

############################################
# SYMBOLIZATION CORE
############################################

# Globals set by `try_symbolize` on success. (Bash doesn't make returning
# multi-line strings from a function pleasant; globals are the simplest path.)
SYM_RESULT_DISPLAY=""
SYM_RESULT_TEXT=""

try_symbolize() {
  local pc="$1" file="$2" display="$3"

  # No `-a`: we already have the address from the trace, and including it
  # makes addr2line print it as line 1 — which then trivially passes the
  # "first line is not '??'" validity check, even when the actual function
  # is unresolved.
  local out
  out=$("$A2L" -f -C -i -e "$file" "$pc" 2>/dev/null || true)

  local func
  func=$(printf '%s\n' "$out" | awk 'NF{print; exit}')

  if [[ -z "$func" || "$func" == "??" ]]; then
    return 1
  fi

  SYM_RESULT_DISPLAY="$display"
  SYM_RESULT_TEXT="$out"
  return 0
}

# Returns:
#   0 — resolved (SYM_RESULT_* populated)
#   1 — Build ID is in the trace but no symbol file matches
#   2 — Build ID matched, but addr2line returned `??` (binary stripped, or PC
#       outside any covered range)
#   3 — frame has no Build ID (system library: libc, libart, libandroid_runtime,
#       …). These are intentionally not symbolized because Codemagic doesn't
#       ship them.
symbolize_pc() {
  local pc="$1" build_id_hint="$2"

  if [[ -z "$build_id_hint" ]]; then
    return 3
  fi

  local matched_any=0 i
  for i in "${!SYMBOL_BUILDIDS[@]}"; do
    if [[ "${SYMBOL_BUILDIDS[$i]}" == "$build_id_hint" ]]; then
      matched_any=1
      if try_symbolize "$pc" "${SYMBOL_FILES[$i]}" "${SYMBOL_DISPLAY[$i]}"; then
        return 0
      fi
    fi
  done

  if (( matched_any == 1 )); then
    return 2
  fi
  return 1
}

############################################
# PROCESS TRACE
############################################

: > "$OUT_FILE"

log "Symbolizing..."

TOTAL=0
RESOLVED=0
UNRESOLVED_NOMATCH=0
UNRESOLVED_STRIPPED=0
SYSTEM=0
# macOS ships bash 3.2 (no associative arrays). Use a space-delimited string
# with sentinel spaces and substring tests for set-membership instead.
UNMATCHED_BUILD_IDS=" "
UNMATCHED_BUILD_IDS_COUNT=0

# `|| [[ -n "$line" ]]` keeps the loop running for a final line that has no
# trailing newline — Play Console exports occasionally come that way, and the
# default `read` would silently drop the last frame.
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ pc\ (0x[0-9a-fA-F]+)[[:space:]]+([^[:space:]]+) ]]; then
    ((++TOTAL))

    pc="${BASH_REMATCH[1]}"
    bin_path="${BASH_REMATCH[2]}"
    build_id=$(printf '%s\n' "$line" \
      | grep -oiE 'BuildId: [0-9a-fA-F]+' \
      | awk '{print tolower($2)}' \
      || true)

    echo "$line" >> "$OUT_FILE"

    # Path-based system classification short-circuits BuildId matching: even
    # frames from `com.google.android.gms` etc. carry a BuildId, but it's
    # Google's, not the user's, and we will never have symbols for it.
    if is_system_path "$bin_path"; then
      echo "    -> [SYSTEM: external/system library not shipped in symbol artefacts]" >> "$OUT_FILE"
      ((++SYSTEM))
      continue
    fi

    if symbolize_pc "$pc" "$build_id"; then
      sym_status=0
    else
      sym_status=$?
    fi

    case "$sym_status" in
      0)
        echo "    -> $SYM_RESULT_DISPLAY" >> "$OUT_FILE"
        echo "$SYM_RESULT_TEXT" >> "$OUT_FILE"
        ((++RESOLVED))
        ;;
      1)
        echo "    -> [UNRESOLVED: no symbol file for BuildId $build_id]" >> "$OUT_FILE"
        ((++UNRESOLVED_NOMATCH))
        if [[ "$UNMATCHED_BUILD_IDS" != *" $build_id "* ]]; then
          UNMATCHED_BUILD_IDS+="$build_id "
          ((++UNMATCHED_BUILD_IDS_COUNT))
        fi
        ;;
      2)
        echo "    -> [UNRESOLVED: BuildId $build_id matched but PC has no debug info (Flutter engine binaries ship stripped)]" >> "$OUT_FILE"
        ((++UNRESOLVED_STRIPPED))
        ;;
      3)
        # Reached when a non-system path has no BuildId. Rare: a user-app
        # frame stripped of its Build ID note, or a system path we don't
        # yet recognise in `is_system_path`.
        echo "    -> [SYSTEM: no BuildId — frame is from a library not shipped in symbol artefacts]" >> "$OUT_FILE"
        ((++SYSTEM))
        ;;
    esac
  else
    echo "$line" >> "$OUT_FILE"
  fi
done < "$TRACE_FILE"

UNRESOLVED=$((UNRESOLVED_NOMATCH + UNRESOLVED_STRIPPED))

############################################
# SUMMARY
############################################

log "Done → $OUT_FILE"

if (( JSON_OUTPUT == 1 )); then
  # All UI/status went to stderr; stdout is exactly one JSON object.
  printf '{"frames":%d,"resolved":%d,"unresolved":%d,"unresolved_nomatch":%d,"unresolved_stripped":%d,"system":%d,"abi":"%s","output":"%s"}\n' \
    "$TOTAL" "$RESOLVED" "$UNRESOLVED" "$UNRESOLVED_NOMATCH" "$UNRESOLVED_STRIPPED" "$SYSTEM" "$ABI" "$OUT_FILE"
else
  echo ""
  echo "========== SUMMARY =========="
  echo "Frames: $TOTAL"
  echo "  Resolved: $RESOLVED"
  echo "  Unresolved: $UNRESOLVED"
  if (( UNRESOLVED_NOMATCH > 0 )); then
    echo "    - no symbol file for BuildId: $UNRESOLVED_NOMATCH"
  fi
  if (( UNRESOLVED_STRIPPED > 0 )); then
    echo "    - BuildId matched, no debug info: $UNRESOLVED_STRIPPED"
  fi
  echo "  System / external: $SYSTEM"

  if (( UNRESOLVED_NOMATCH > 0 )); then
    echo ""
    warn "$UNMATCHED_BUILD_IDS_COUNT BuildId(s) in the trace had no matching symbol file:"
    # `for bid in $UNMATCHED_BUILD_IDS` relies on word-splitting; quoting would
    # treat the whole list as a single token. shellcheck disable=SC2086.
    # shellcheck disable=SC2086
    for bid in $UNMATCHED_BUILD_IDS; do
      echo "  - $bid"
    done
    echo "Most likely cause: the symbol artefacts are from a different build."
    echo "Re-run codemagic_fetch_artifacts.py with the version that produced the crash."
  fi
fi
