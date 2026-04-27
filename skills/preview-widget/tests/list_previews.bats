#!/usr/bin/env bats
# Tests for list_previews.sh — annotation + class-definition discovery.

load helpers

setup()    { pw_setup; }
teardown() { pw_teardown; }

@test "lists @Preview annotations with file:line references" {
  proj=$(make_lib_tree)
  run_list_in "$proj"
  [ "$status" -eq 0 ]

  [[ "$output" == *"lib/widgets/button.dart"* ]]
  [[ "$output" == *"@Preview(name:"* ]]
}

@test "lists multiple @Preview annotations on the same file" {
  proj=$(make_lib_tree)
  run_list_in "$proj"
  [ "$status" -eq 0 ]

  count=$(printf '%s\n' "$output" | grep -c '@Preview(' || true)
  [ "$count" -ge 2 ]
}

@test "lists custom @StandardPreview annotation usage" {
  proj=$(make_lib_tree)
  run_list_in "$proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"@StandardPreview()"* ]]
  [[ "$output" == *"lib/widgets/card.dart"* ]]
}

@test "lists \"extends MultiPreview\" class definitions" {
  proj=$(make_lib_tree)
  run_list_in "$proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"extends MultiPreview"* ]]
  [[ "$output" == *"lib/preview_variants.dart"* ]]
}

@test "scoped scan via positional arg only walks the given root" {
  proj=$(make_lib_tree)
  run_list_in "$proj" "lib/widgets"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/widgets/button.dart"* ]]
  [[ "$output" == *"lib/widgets/card.dart"* ]]
  # preview_variants.dart lives one level up from widgets/, so it should be
  # excluded here.
  [[ "$output" != *"preview_variants.dart"* ]]
}

@test "ignores non-Dart files even if they contain @Preview" {
  proj=$(make_lib_tree)
  cat > "$proj/lib/widgets/notes.txt" <<'EOF'
@Preview(name: 'Should not match')
EOF
  run_list_in "$proj"
  [ "$status" -eq 0 ]
  [[ "$output" != *"notes.txt"* ]]
  [[ "$output" != *"Should not match"* ]]
}

@test "does not match @PreviewSomething (suffix-bound only)" {
  proj=$(make_lib_tree)
  cat > "$proj/lib/widgets/decoy.dart" <<'EOF'
class PreviewSomething {}
@PreviewSomethingElse(name: 'fake')
class Decoy {}
EOF
  run_list_in "$proj"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PreviewSomethingElse"* ]]
}

@test "empty project (no Dart files with previews) prints nothing and exits 0" {
  mkdir -p "$TEST_TMP/empty/lib"
  echo "// no previews" > "$TEST_TMP/empty/lib/foo.dart"
  run_list_in "$TEST_TMP/empty"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
