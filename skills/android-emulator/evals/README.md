# Evals for `android-emulator`

- [`eval_queries.json`](eval_queries.json) — trigger evals. Format and runner: [optimizing-descriptions](https://agentskills.io/skill-creation/optimizing-descriptions).
- [`evals.json`](evals.json) — behavior evals. Format and runner: [evaluating-skills](https://agentskills.io/skill-creation/evaluating-skills).

Both formats run end-to-end with [`skill-creator`](https://github.com/anthropics/skills/tree/main/skills/skill-creator).

## Environment for the behavior eval

`evals.json` drives a real device. Needs Android SDK (`adb` + `emulator` on `$PATH`) with at least one AVD, Flutter (or [`fvm`](https://fvm.app/)), macOS (for `sips`), and a Flutter project for `$PWD` to walk up from. `eval_queries.json` needs none of this.

## Local run protocol

For runs from this repo on a developer machine — idempotent, leaves no installed-skill artifacts:

- **Runner:** manual `claude -p` per the script template in [optimizing-descriptions](https://agentskills.io/skill-creation/optimizing-descriptions#running-multiple-times). Not skill-creator.
- **Skill install:** project-scoped symlink, set up and torn down per run. From the eval cwd:

  ```bash
  SKILL_SRC="$(git -C /path/to/this/repo rev-parse --show-toplevel)/skills/android-emulator"
  setup()    { mkdir -p .claude/skills && ln -sfn "$SKILL_SRC" .claude/skills/android-emulator; }
  teardown() { rm -f .claude/skills/android-emulator; rmdir .claude/skills .claude 2>/dev/null || true; }
  trap teardown EXIT
  setup
  ```

  `ln -sfn` force-relinks (idempotent re-runs), the `trap` ensures cleanup even on Ctrl-C, and the `rmdir` calls only remove `.claude/` if they're empty (so the developer's existing `.claude/` content is never touched). Works regardless of whether the developer has the skill installed globally — but for the behavior eval's `without_skill` baseline to be a true baseline, also ensure the skill isn't installed at `~/.claude/skills/android-emulator`.
- **cwd:** `~/git/pixel-buddy-app` for both suites. Trigger queries imply a Flutter context; the behavior eval needs a real `pubspec.yaml` to walk up from.

## For AI agents

Repo policy is to ask the developer before running — see [AGENTS.md](../../../AGENTS.md). Skill-specific cost note for the prompt: trigger evals are cheap; the behavior eval needs the environment above and spawns two subagent runs per test case.
