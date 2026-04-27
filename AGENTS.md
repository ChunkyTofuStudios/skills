# Contributing skills

This repo hosts open-source [Agent Skills](https://agentskills.io/) developed at [Chunky Tofu Studios](https://chunkytofustudios.com/), focused on AI-assisted Flutter development. Consumers should read [README.md](README.md); this file is for anyone — human or agent — adding or editing a skill here.

If you're new to Agent Skills, start with the canonical docs and come back:

- [Specification](https://agentskills.io/specification) — `SKILL.md` format, frontmatter fields, directory layout.
- [Quickstart](https://agentskills.io/skill-creation/quickstart) — minimal working skill in one file.
- [Best practices](https://agentskills.io/skill-creation/best-practices) — what makes a skill effective.
- [Optimizing descriptions](https://agentskills.io/skill-creation/optimizing-descriptions) — the `description` field is the trigger; this is how to tune it.
- [Using scripts in skills](https://agentskills.io/skill-creation/using-scripts) — script conventions, error handling, structured output.
- [`skill-creator`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) — Anthropic's practical reference for writing and iterating on skills end-to-end.

The rest of this doc is just the conventions specific to *this* repo.

## Repo conventions

**Layout.** Each skill lives at `skills/<skill-name>/`, where `<skill-name>` exactly matches the `name` field in its `SKILL.md`. Bundle helpers under `scripts/`, on-demand docs under `references/`, and templates/fixtures under `assets/` — per the [spec](https://agentskills.io/specification#optional-directories).

**Frontmatter.** In addition to the required `name` and `description` fields, set:

```yaml
license: MIT
metadata:
  author: Chunky Tofu Studios
  source: https://github.com/chunkytofustudios/flutter-skills
```

`license: MIT` ensures consumers who pull a skill standalone still see the [repo license](LICENSE). `metadata.source` lets them find updates.

**Register the skill in two places.** When adding a new skill:

1. Add a row to the *Available skills* table in [README.md](README.md).
2. Append a plugin entry to [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) so Claude Code users can `/plugin install <skill>@chunkytofustudios`. Mirror the existing `android-emulator` entry — same `source`, set `skills` to `["./skills/<skill-name>"]`, and copy `description` from the skill's frontmatter so the marketplace listing matches what triggers the skill.

**Validation.** Run [`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref) before opening a PR:

```bash
skills-ref validate skills/<your-skill>
```

**Unit tests, lint, type check.** Three repo-wide gates live in [`tools/`](tools/):

```bash
tools/run-tests.sh                # bats + python unittest suites under skills/*/tests/
tools/run-tests.sh skills/<name>  # scope to one skill (also accepts skills/<name>/tests)
tools/lint.sh                     # shellcheck on every bundled shell script
tools/typecheck.sh                # `ty` (Astral) on every bundled python script
```

`run-tests.sh` discovers two test types per skill: `*.bats` files (run with `bats`) and `test_*.py` files (run with `python3 -m unittest`). Skills without a `tests/` directory are skipped — adding a suite is a welcome contribution. See [`skills/android-emulator/tests/`](skills/android-emulator/tests/) for a bats-only layout, and [`skills/symbolize-android-stacktrace/tests/`](skills/symbolize-android-stacktrace/tests/) for a mixed bats + python layout.

**If you modify any shell script under `skills/<name>/scripts/` (or `tools/`), run lint and tests before reporting the change as done. If you modify any python script, also run `tools/typecheck.sh`.** All three are fast (<5s), need no emulator or network, and catch the most common regressions. Required deps:

- `bats-core` + `shellcheck` (`brew install bats-core shellcheck` on macOS)
- `python3` (3.10+) — stdlib only, no test deps
- `ty` via `uv` (`brew install uv` on macOS); the script falls back to `uvx ty` if `ty` isn't on PATH

Each tool exits 127 with a clear install hint when its dependency is missing.
