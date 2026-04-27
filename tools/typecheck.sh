#!/usr/bin/env bash
# Run `ty` (Astral's Python type checker) over every Python script bundled
# with a skill. Discovers files under skills/*/scripts/*.py. Pass paths as
# arguments to scope to specific files.
#
# Tests under skills/*/tests/test_*.py are intentionally excluded — they
# use a runtime sys.path trick (inserting ../scripts/) that ty can't see
# without project-level configuration. The trade-off is OK: tests run
# under unittest, and the scripts they import are themselves type-checked
# by this gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# `ty` is distributed by Astral. Prefer a global install on PATH; fall back
# to `uvx ty` (downloads on first use, then caches) if `uv` is available.
if command -v ty >/dev/null 2>&1; then
  TY=(ty)
elif command -v uvx >/dev/null 2>&1; then
  TY=(uvx ty)
else
  cat >&2 <<'EOF'
error: neither `ty` nor `uvx` is on PATH.
Install one of:
  macOS / Linux:  brew install uv          # then `uvx ty` works
  or:             cargo install ty         # native binary
  or:             pipx install ty
EOF
  exit 127
fi

if [ "$#" -gt 0 ]; then
  FILES=("$@")
else
  FILES=()
  while IFS= read -r f; do FILES+=("$f"); done < <(
    find skills -type f -path '*/scripts/*.py' 2>/dev/null | sort
  )
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no python scripts found to type-check" >&2
  exit 0
fi

echo "ty: ${#FILES[@]} file(s)"
"${TY[@]}" check "${FILES[@]}"
echo "OK: ty clean"
