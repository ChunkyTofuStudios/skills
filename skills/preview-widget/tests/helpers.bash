# Common bats helpers for preview-widget tests. Source via:
#
#   load helpers
#
# Provides:
#   - pw_setup / pw_teardown:     per-test sandbox + cleanup of any background
#                                 server the test might leave behind.
#   - run_check / run_start /
#     run_screenshot / run_list:  thin wrappers that run each script as a
#                                 subprocess via bats's `run`.
#   - PW_FIXTURES_DIR / PW_STUBS_DIR: paths into the bundled test data.
#   - assert_called / refute_called: query the stub call log.

# shellcheck disable=SC2034  # consumed by .bats files via `load helpers`
PW_SCRIPTS_DIR="$BATS_TEST_DIRNAME/../scripts"
# shellcheck disable=SC2034
PW_STUBS_DIR="$BATS_TEST_DIRNAME/stubs"
# shellcheck disable=SC2034
PW_FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

pw_setup() {
  TEST_TMP="$(mktemp -d)"
  STUB_LOG="$TEST_TMP/calls.log"
  : > "$STUB_LOG"

  export STUB_LOG TEST_TMP

  # Per-test isolated state and output directories so concurrent test files
  # never collide and the project tree stays clean.
  export PREVIEW_WIDGET_STATE_DIR="$TEST_TMP/state"
  export PREVIEW_WIDGET_OUT_DIR="$TEST_TMP/out"

  # Default stub URL the fake `flutter` binary advertises.
  export STUB_FLUTTER_URL="http://localhost:51530"

  # Prepend stubs so they shadow real `flutter`, `chrome`, `nohup`. We keep
  # the rest of PATH (awk/grep/find/...) intact.
  export PATH="$PW_STUBS_DIR:$PATH"

  # The scripts' default `flutter` lookup uses `command -v flutter`. We rely
  # on the stub being on PATH; FLUTTER_BIN stays unset so the auto-detect
  # branch is exercised.
  unset FLUTTER_BIN || true
  unset CHROME_BIN  || true
}

pw_teardown() {
  # Best-effort: if a test left a server PID in the state file, kill it so
  # background stub processes don't leak across tests.
  if [ -n "${PREVIEW_WIDGET_STATE_DIR:-}" ] \
      && [ -f "${PREVIEW_WIDGET_STATE_DIR}/server.json" ]; then
    pid=$(awk -F '[[:space:],]+' '/"pid"/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) {print $i; exit}}' \
      "${PREVIEW_WIDGET_STATE_DIR}/server.json" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  fi

  if [ -n "${TEST_TMP:-}" ] && [ -d "$TEST_TMP" ]; then
    rm -rf "$TEST_TMP"
  fi
}

run_check()      { run "$PW_SCRIPTS_DIR/check_preview_support.sh" "$@"; }
run_start()      { run "$PW_SCRIPTS_DIR/start_preview.sh" "$@"; }
run_screenshot() { run "$PW_SCRIPTS_DIR/screenshot_preview.sh" "$@"; }
run_list()       { run "$PW_SCRIPTS_DIR/list_previews.sh" "$@"; }

# Run list_previews.sh from inside <dir>. We can't use `( cd … && run_list )`
# because `run` mutates $status / $output in its caller's scope, and a
# subshell wall stops those from reaching the bats test that needs them.
# This function does the cd in the function's own scope, calls `run`, then
# restores $PWD before returning — leaving $status / $output set for the test.
run_list_in() {
  local dir="$1"; shift
  local prev="$PWD"
  cd "$dir" || return 1
  run "$PW_SCRIPTS_DIR/list_previews.sh" "$@"
  cd "$prev" || return 1
}

assert_called() {
  local pattern="$1"
  if ! grep -F -- "$pattern" "$STUB_LOG" >/dev/null 2>&1; then
    {
      printf 'expected stub call matching: %s\n' "$pattern"
      printf -- '--- actual call log ---\n'
      cat "$STUB_LOG" 2>/dev/null || echo '(empty)'
      printf -- '-----------------------\n'
    } >&2
    return 1
  fi
}

refute_called() {
  local pattern="$1"
  if grep -F -- "$pattern" "$STUB_LOG" >/dev/null 2>&1; then
    {
      printf 'unexpected stub call matching: %s\n' "$pattern"
      printf -- '--- actual call log ---\n'
      cat "$STUB_LOG" 2>/dev/null || echo '(empty)'
      printf -- '-----------------------\n'
    } >&2
    return 1
  fi
}

# Build a fixture lib/ tree under $TEST_TMP. Returns the project root.
# Usage: proj=$(make_lib_tree)
make_lib_tree() {
  local root="$TEST_TMP/proj"
  mkdir -p "$root/lib/widgets" "$root/lib/screens"

  cat > "$root/lib/widgets/button.dart" <<'EOF'
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../preview_wrapper.dart';

@Preview(name: 'Button — light', wrapper: previewWrapper)
Widget buttonPreviewLight() => const ElevatedButton(onPressed: null, child: Text('Hi'));

@Preview(name: 'Button — dark', brightness: Brightness.dark, wrapper: previewWrapper)
Widget buttonPreviewDark() => const ElevatedButton(onPressed: null, child: Text('Hi'));
EOF

  cat > "$root/lib/widgets/card.dart" <<'EOF'
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../preview_variants.dart';

@StandardPreview()
Widget cardPreview() => const Card(child: SizedBox(width: 200, height: 80));
EOF

  cat > "$root/lib/preview_variants.dart" <<'EOF'
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'preview_wrapper.dart';

final class StandardPreview extends MultiPreview {
  const StandardPreview();

  @override
  final List<Preview> previews = const <Preview>[
    Preview(name: 'Light', brightness: Brightness.light, wrapper: previewWrapper),
  ];
}
EOF

  cat > "$root/lib/screens/home.dart" <<'EOF'
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}
EOF

  echo "$root"
}
