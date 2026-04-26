# Evals for `android-emulator`

- [`eval_queries.json`](eval_queries.json) — trigger evals. Format and runner: [optimizing-descriptions](https://agentskills.io/skill-creation/optimizing-descriptions).
- [`evals.json`](evals.json) — behavior evals. Format and runner: [evaluating-skills](https://agentskills.io/skill-creation/evaluating-skills).

Both formats run end-to-end with [`skill-creator`](https://github.com/anthropics/skills/tree/main/skills/skill-creator).

## Environment for the behavior eval

`evals.json` drives a real device. Needs Android SDK (`adb` + `emulator` on `$PATH`) with at least one AVD, Flutter (or [`fvm`](https://fvm.app/)), macOS (for `sips`), and a Flutter project for `$PWD` to walk up from. `eval_queries.json` needs none of this.

## For AI agents

Repo policy is to ask the developer before running — see [AGENTS.md](../../../AGENTS.md). Skill-specific cost note for the prompt: trigger evals are cheap; the behavior eval needs the environment above and spawns two subagent runs per test case.
