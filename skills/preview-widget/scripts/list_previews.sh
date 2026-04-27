#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# CONFIG / INPUT
############################################

usage() {
  cat <<EOF
Usage: $0 [<root>]

Lists every \`@Preview(...)\`, \`@<Custom>Preview(...)\` annotation, and
\`extends Preview\` / \`extends MultiPreview\` class definition in a
Flutter project. Output format: \`path:line: matched_text\`.

Args:
  <root>  Directory to scan. Default: \`lib\`.

Flags:
  -h, --help  Show this help.

Exit codes:
  0    Scan completed (zero or more matches printed).
  1    Root directory does not exist.
EOF
}

############################################
# LOGGING
############################################

error() { echo "[ERROR] $*" >&2; }

############################################
# ARG PARSING
############################################

ROOT="lib"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*) error "Unknown flag: $1"; usage; exit 1 ;;
    *)
      ROOT="$1"
      shift
      ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  error "Not a directory: $ROOT"
  exit 1
fi

############################################
# SCAN
############################################

# Two passes, then merged + sorted:
#   1. Annotation usages: lines starting with @<MaybePrefix>Preview(...).
#      Pattern `@[A-Za-z0-9_]*Preview\b` matches both bare `@Preview` (empty
#      prefix) and `@FooPreview`, but NOT `@PreviewSomething`.
#   2. Class definitions: `... extends (Multi)?Preview` or any custom subclass
#      (`extends FooPreview`).
#
# `|| true` after each grep so the "no matches" exit-1 doesn't trip set -e.

annotation_re='@[A-Za-z0-9_]*Preview[[:space:]]*\('
class_re='extends[[:space:]]+[A-Za-z0-9_]*Preview\b'

{
  grep -RHnE --include='*.dart' "$annotation_re" "$ROOT" 2>/dev/null || true
  grep -RHnE --include='*.dart' "$class_re"      "$ROOT" 2>/dev/null || true
} | sort -u
