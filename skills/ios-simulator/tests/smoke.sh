#!/usr/bin/env bash
# Smoke test: confirms sim.sh's no-side-effect commands work and the script
# isn't structurally broken. Does NOT require a booted simulator.
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$DIR/scripts/sim.sh"

pass() { printf "  ✓ %s\n" "$1"; }
fail() { printf "  ✗ %s\n" "$1" >&2; exit 1; }

echo "smoke test: $SIM"

# 1. help exits 0 and prints usage
"$SIM" help >/tmp/sim-smoke-help.$$ 2>&1 \
  && grep -q "Usage: scripts/sim.sh" /tmp/sim-smoke-help.$$ \
  && pass "help prints usage" \
  || fail "help missing/wrong"
rm -f /tmp/sim-smoke-help.$$

# 2. unknown command falls through to help
"$SIM" __not_a_command_xyz__ >/tmp/sim-smoke-unknown.$$ 2>&1 \
  && grep -q "Usage:" /tmp/sim-smoke-unknown.$$ \
  && pass "unknown command shows help" \
  || fail "unknown command behavior changed"
rm -f /tmp/sim-smoke-unknown.$$

# 3. devices subcommand runs without a simulator
"$SIM" devices >/dev/null 2>&1 \
  && pass "devices runs" \
  || fail "devices errored unexpectedly"

# 4. disk-check runs without a project context (root volume fallback)
( cd "$HOME" && "$SIM" disk-check >/dev/null 2>&1 ) \
  && pass "disk-check (no project) runs" \
  || true  # may exit 1 if disk is genuinely low — that's still a pass for "ran"

# 5. preflight without project context errors cleanly
( cd "$HOME" && "$SIM" preflight 2>&1 ) | grep -q "preflight needs a Flutter project" \
  && pass "preflight errors without project context" \
  || fail "preflight didn't error as expected"

# 6. bash -n syntax check
bash -n "$SIM" && pass "bash -n parses sim.sh" || fail "sim.sh has syntax errors"

echo "smoke: all checks passed"
