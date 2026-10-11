# Agent skills for Glyph

Portable [Agent Skills](https://agentskills.io) that let an AI coding agent
contribute to Glyph.

| Skill | What it does |
|---|---|
| [`glyph-animation`](glyph-animation/SKILL.md) | Draws a new pixel-art animation in Glyph's sprite format, validates and previews it, and opens a pull request. |

Each skill is a folder with a `SKILL.md` (instructions), reference notes and
scripts. The validator needs only Python 3:

```bash
python3 skills/glyph-animation/scripts/validate_sprite.py --all
python3 skills/glyph-animation/scripts/validate_sprite.py --pack assets/catalog/sprites/nature.json --only <id> --preview build/<id>.png
```

## Use with your agent

**Claude Code.** Install from this repo's plugin marketplace:

```
/plugin marketplace add spandan-kumar/glyph
/plugin install glyph-animation@glyph
```

Then ask "draw a Glyph animation of a sleepy cat" (or run
`/glyph-animation:glyph-animation`). Alternatively copy
`skills/glyph-animation/` to `~/.claude/skills/` (all projects) or
`.claude/skills/` (one project).

**Codex, Cursor, Gemini CLI, Copilot and others.** Work inside a Glyph
checkout and point the agent at `skills/glyph-animation/SKILL.md`;
`AGENTS.md` already tells agents to use it for animation tasks. Tools with a
skills folder can load a copy of `skills/glyph-animation/` directly.

**Plain chat.** Paste `SKILL.md` and `reference.md` into the conversation,
draw together, then run the validator and open the pull request yourself.

Everything an agent draws must be original or public domain; see
[CONTRIBUTING.md](../CONTRIBUTING.md#licensing-original-or-public-domain-only).
