# Common bats helpers for symbolize-android-stacktrace tests. Source via:
#
#   load helpers
#
# Provides:
#   - sym_setup: per-test sandbox with a fake NDK on ANDROID_NDK_HOME
#   - sym_teardown: cleanup
#   - run_sym:  run symbolize_flutter_anr.sh as a subprocess
#   - SYM_FIXTURES_DIR / SYM_STUBS_DIR: paths into the test data

# shellcheck disable=SC2034  # consumed by .bats files via `load helpers`
SYM_SCRIPT="$BATS_TEST_DIRNAME/../scripts/symbolize_flutter_anr.sh"
# shellcheck disable=SC2034
SYM_FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"
# shellcheck disable=SC2034
SYM_STUBS_DIR="$BATS_TEST_DIRNAME/stubs"

sym_setup() {
  TEST_TMP="$(mktemp -d)"
  STUB_LOG="$TEST_TMP/calls.log"
  : > "$STUB_LOG"

  export STUB_LOG TEST_TMP

  # Point the script at the bundled fake NDK. The `bats-host` directory exists
  # under stubs/ndk/toolchains/llvm/prebuilt/, satisfying the script's
  # `find … -mindepth 1 -maxdepth 1 -type d` lookup.
  export ANDROID_NDK_HOME="$SYM_STUBS_DIR/ndk"
}

sym_teardown() {
  if [ -n "${TEST_TMP:-}" ] && [ -d "$TEST_TMP" ]; then
    rm -rf "$TEST_TMP"
  fi
}

run_sym() {
  run "$SYM_SCRIPT" "$@"
}

# Copy a fixture trace into the per-test temp dir so the script can write
# its <trace>.symbolized.txt next to it without polluting the source tree.
# Usage: trace=$(stage_trace play-anr-trace.log)
stage_trace() {
  local name="$1"
  local dest="$TEST_TMP/$name"
  cp "$SYM_FIXTURES_DIR/$name" "$dest"
  echo "$dest"
}
