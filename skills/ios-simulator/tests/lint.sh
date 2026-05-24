#!/usr/bin/env bash
# Lint sim.sh with shellcheck. No-op if shellcheck isn't installed.
# Install: brew install shellcheck
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$DIR/scripts/sim.sh"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "skipping: shellcheck not installed (brew install shellcheck)"
  exit 0
fi

# -x follows sourced files; -e SC1091 silences "can't follow" warnings for
# files outside the repo. We keep external warnings off but want all real
# bash issues to surface.
shellcheck -x -e SC1091 "$SIM"
echo "shellcheck: clean"
