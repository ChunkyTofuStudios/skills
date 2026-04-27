#!/usr/bin/env bash
# Run every skill's test suite. Each skill that ships tests puts them under
# skills/<name>/tests/. Two test types are discovered automatically:
#
#   *.bats       — bash test files, run with `bats`
#   test_*.py    — Python unittest files, run with `python3 -m unittest`
#
# Skills without a tests/ directory are skipped — adding tests to a skill is
# a welcome contribution; see skills/android-emulator/tests/ (bats) and
# skills/symbolize-android-stacktrace/tests/ (bats + python) for the layout.
#
# Pass `tools/run-tests.sh skills/<name>` (or `skills/<name>/tests`) to scope
# to one skill, or pass an explicit `*.bats` file to run a single suite.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

require_cmd() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    cat >&2 <<EOF
error: \`$cmd\` is not installed.
Install with:
$install_hint
EOF
    exit 127
  fi
}

# Allow `tools/run-tests.sh skills/foo` (or skills/foo/tests, or a single
# .bats file) to scope to one skill, otherwise discover all skills/*/tests.
TARGETS=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    # Accept `skills/foo`, `skills/foo/`, and `skills/foo/tests` interchangeably.
    if [ -d "$arg/tests" ]; then
      TARGETS+=("$arg/tests")
    else
      TARGETS+=("$arg")
    fi
  done
else
  for d in skills/*/tests; do
    [ -d "$d" ] || continue
    TARGETS+=("$d")
  done
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "no skill test directories found under skills/*/tests" >&2
  exit 0
fi

# First pass: figure out which runners we'll need and validate inputs. We
# probe the deps up front so the caller gets a clean install hint instead
# of a cryptic mid-run "command not found".
need_bats=0
need_py=0
for target in "${TARGETS[@]}"; do
  if [ -d "$target" ]; then
    if find "$target" -maxdepth 2 -name '*.bats' -type f -print -quit 2>/dev/null | grep -q .; then
      need_bats=1
    fi
    if find "$target" -maxdepth 2 -name 'test_*.py' -type f -print -quit 2>/dev/null | grep -q .; then
      need_py=1
    fi
  elif [ -f "$target" ]; then
    case "$target" in
      *.bats) need_bats=1 ;;
      *.py)   need_py=1 ;;
      *) ;; # rejected later with a "skip:" message
    esac
  fi
done

if [ "$need_bats" -eq 1 ]; then
  require_cmd bats $'  macOS:  brew install bats-core\n  Linux:  apt-get install bats   (or: npm install -g bats)'
fi
if [ "$need_py" -eq 1 ]; then
  require_cmd python3 $'  macOS:  brew install python\n  Linux:  apt-get install python3'
fi

ran_anything=0
fail=0

run_bats_in_dir() {
  local dir="$1"
  local files=()
  while IFS= read -r f; do files+=("$f"); done \
    < <(find "$dir" -maxdepth 2 -name '*.bats' -type f | sort)
  if [ "${#files[@]}" -eq 0 ]; then return 0; fi
  printf '\n=== bats: %s ===\n' "$dir"
  if ! bats "${files[@]}"; then fail=1; fi
  ran_anything=1
}

run_py_in_dir() {
  local dir="$1"
  if ! find "$dir" -maxdepth 2 -name 'test_*.py' -type f -print -quit | grep -q .; then
    return 0
  fi
  printf '\n=== python: %s ===\n' "$dir"
  # `-t $dir` so test modules can import their own siblings (e.g. helpers
  # under tests/). `-b` buffers stdout from passing tests so warn() output
  # from imported scripts doesn't drown the pass/fail summary.
  if ! python3 -m unittest discover -s "$dir" -p 'test_*.py' -t "$dir" -b; then
    fail=1
  fi
  ran_anything=1
}

for target in "${TARGETS[@]}"; do
  if [ -d "$target" ]; then
    run_bats_in_dir "$target"
    run_py_in_dir "$target"
  elif [ -f "$target" ]; then
    case "$target" in
      *.bats)
        printf '\n=== bats: %s ===\n' "$target"
        if ! bats "$target"; then fail=1; fi
        ran_anything=1
        ;;
      *.py)
        # Single python file: run from its parent directory so `-t` works.
        dir="$(dirname "$target")"
        base="$(basename "$target")"
        printf '\n=== python: %s ===\n' "$target"
        if ! python3 -m unittest discover -s "$dir" -p "$base" -t "$dir" -b; then
          fail=1
        fi
        ran_anything=1
        ;;
      *)
        echo "skip: $target (unrecognized file extension; want *.bats or test_*.py)" >&2
        ;;
    esac
  else
    echo "skip: $target (not a directory or test file)" >&2
  fi
done

if [ "$ran_anything" -eq 0 ]; then
  echo "no test files found under: ${TARGETS[*]}" >&2
  exit 0
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "FAIL: one or more test suites failed" >&2
  exit 1
fi

echo
echo "OK: all test suites passed"
