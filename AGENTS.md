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
  source: https://github.com/chunkytofustudios/skills
```

`license: MIT` ensures consumers who pull a skill standalone still see the [repo license](LICENSE). `metadata.source` lets them find updates.

**Validation.** Run [`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref) before opening a PR:

```bash
skills-ref validate skills/<your-skill>
```

**Tests / evals.** Out of scope for the moment. Contributions welcome — follow the [`skill-creator` workflow](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) and put fixtures under `evals/` in the skill directory.
