# CTS Agent Skills

Open-source [Agent Skills](https://agentskills.io/) for AI-assisted Flutter development, maintained by [Chunky Tofu Studios](https://chunkytofustudios.com/).

A skill is a self-contained directory that gives an AI coding agent specialized capabilities — domain-specific procedures, scripts, and gotchas — that load on demand only when relevant. The format is open and works in any compatible agent: [Claude Code](https://claude.com/claude-code), [OpenAI Codex](https://github.com/openai/codex), [GitHub Copilot in VS Code](https://docs.github.com/en/copilot), and others.

## Available skills

| Skill | What it does |
|---|---|
| [`android-emulator`](skills/android-emulator/) | Run, debug, screenshot, and interact with a Flutter app on an Android emulator. Gives the agent eyes (screenshots, accessibility tree) and hands (tap, hold, swipe, multi-touch pinch). |

More skills will land here over time.

## Installing a skill

Two supported paths: [skills.sh](#install-via-skillssh) (works with any compatible agent) and the [Claude Code plugin marketplace](#install-via-claude-code-plugins) (Claude Code only). Pick whichever fits your setup.

### Install via skills.sh

Use [skills.sh](https://skills.sh) — the open agent-skills package manager — to install skills from this repo into your project. From your Flutter project's root:

```bash
# Install everything in this repo
npx skills add chunkytofustudios/skills

# Or just one skill
npx skills add chunkytofustudios/skills --skill android-emulator
```

`npx skills` auto-detects the agents you have set up (Claude Code, Cursor, GitHub Copilot in VS Code, OpenAI Codex, Cline, Windsurf, and 40+ others) and writes the skill into the right place — e.g. `.claude/skills/android-emulator/` for Claude Code or `.agents/skills/android-emulator/` for VS Code. Pin a target with `-a`:

```bash
npx skills add chunkytofustudios/skills --agent claude-code
```

Install globally for all your projects with `-g`:

```bash
npx skills add chunkytofustudios/skills --global
```

Other useful commands:

```bash
npx skills list                  # what's installed
npx skills update                # pull the latest version of installed skills
npx skills remove android-emulator
```

Browse this repo's skills on [skills.sh/chunkytofustudios/skills](https://skills.sh/chunkytofustudios/skills).

### Install via Claude Code plugins

This repo doubles as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins), so [Claude Code](https://claude.com/claude-code) users can install skills directly without `npx skills`. Inside Claude Code:

```text
/plugin marketplace add chunkytofustudios/skills
/plugin install android-emulator@chunkytofustudios
```

The first command registers this repo as a marketplace named `chunkytofustudios`; the second installs a single skill from it. Run `/plugin` on its own to browse what's available, update, or uninstall. Each skill listed in [Available skills](#available-skills) is published as its own plugin under the `chunkytofustudios` marketplace, so you only install what you need.

### Other install paths

If you'd rather not depend on `npx skills` or the plugin marketplace, every skill in this repo is a self-contained directory under `skills/` — copy or symlink one into your agent's skills directory (`.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, …) and it will be picked up.

## Contributing

We welcome new skills and improvements. See [AGENTS.md](AGENTS.md) for the contributor guide — directory layout, frontmatter rules, scripting conventions, and where to learn more about writing good skills.

## License

[MIT](LICENSE) © Chunky Tofu Studios.
