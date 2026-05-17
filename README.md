# claude-skill-router

> Smart skill router for Claude Code — auto-injects SKILL.md content based on prompt context

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## TL;DR

- **What it does:** auto-detects which skill applies to your prompt and injects the full `SKILL.md` content into Claude Code's context, so the model follows the skill protocol without you (or it) having to call the `Skill` tool manually.
- **Why it matters:** as your skill library grows (50, 100, 300+ skills), discovery breaks down. Manual `Skill("X")` calls clutter the chat, the model forgets they exist, and you lose the workflows you carefully designed. This router fixes that with deterministic detection + context injection + an optional gate.
- **Install in one command:** `npx skills add David-CKS/claude-skill-router@router -g -y`

## The problem it solves

Claude Code has hundreds of skills available across `~/.claude/skills/`, `~/.claude/plugins/cache/`, and marketplace installs. The default `Skill` tool requires manual invocation — meaning the model has to *remember* a skill exists, decide it applies, and call it. In practice that fails: skills go ghost, the chat fills with `Skill("X")` tool calls, and complex workflows get skipped.

This router solves it three ways:

1. **Detection:** classifies every prompt against a YAML registry of clusters (keyword + Gemini Flash semantic + FAISS embeddings fallback).
2. **Context injection:** loads the relevant `SKILL.md` and injects its content directly into Claude's reminder block. The model proceeds with the skill protocol automatically — no `Skill` tool call in the chat.
3. **Gate (optional):** for clusters that *must* run a skill (e.g. `commit_push_pr`), enforces it with a grace period (warning first, block second).

## Features

- 🎯 **Cluster-based detection** — keyword match + Gemini Flash semantic classification + optional FAISS embeddings fallback for semantic search across skill descriptions.
- ⚡ **Context Injection** — `SKILL.md` content auto-loaded into the prompt reminder block. No noisy `Skill` tool call required.
- 🚦 **Gate with grace period** — clusters can declare `gate: true`. First tool call without invoking the skill → warning. Second call → `deny` until skill is invoked or grace TTL expires.
- 📊 **Audit log (JSONL)** — every routing decision logged with rotation (1 file/day) + retention (90d) + PII scrub (JWT, Bearer, API keys, Slack tokens).
- 🔄 **Auto-evolution weekly report** — detects ghost skills, cold clusters, gap queries (prompts that activated no cluster) and false positives. Renders markdown report + optional Telegram delivery.
- 🖥️ **Dashboard web** — FastAPI + HTMX + Tailwind on `127.0.0.1:9300`. Live overview, cluster editor with validation, audit log viewer, charts.
- 🌍 **Multi-project clusters** — drop `clusters.local.yaml` in any repo under `~` and it merges with the global registry (same `id` replaces, new `id` adds).
- 🧰 **Bypass tokens** — `[raw]`, `[no-skill]`, `[force-tool]`, `[skip-cluster:X]` for surgical override per prompt.
- 🔬 **Tests included** — 20+ pytest tests across all components (router core, embeddings fallback, context injection, dashboard E2E, evolve detectors).

## Install

```bash
# 1. Pull the skill bundle from GitHub
npx skills add David-CKS/claude-skill-router@router -g -y

# 2. Wire up Claude Code hooks (idempotent)
bash ~/.agents/skills/router/scripts/install.sh

# 3. Restart Claude Code (or open a new session)
```

That's it. Type a prompt — the router classifies it, suggests/injects the relevant skill, and Claude proceeds.

## Battle-tested

Validated in real production sessions before v1.0.0 release. Sample metrics from a single 6h CKS engineering session on 17-may-2026:

| Metric | Value |
|---|---|
| Skills invoked via `Skill` tool | ~25 (commit-work, verification-before-completion, dispatching-parallel-agents, worktree-sync-pro, systematic-debugging, ...) |
| Distinct clusters auto-activated | 8 (`cks_session`, `commit_push_pr`, `agent_dispatch_bg`, `code_implementation`, `skill_creation`, `supabase`, `kommo_n8n`, `worktree_ops`) |
| Consecutive `git push` operations with Context Injection (no friction) | 5/5 |
| Background `Agent` launches detected via `tool_match` (zero ceremony) | 4/4 |
| Gate blocks resolved successfully via skill invocation | ~10 |
| `[force-tool]` overrides needed | 0 |
| False positives detected (motivated `path_excludes` feature) | 3 |

The 3 false positives — `code_implementation` activating on `**/api/**/*.ts` endpoints and `**/*.test.ts` test files when they should be scoped to `**/components/**/*.tsx` only — drove the `path_includes` / `path_excludes` schema added in v1.0.0. See [docs/CASE-STUDY-CKS-17MAY.md](docs/CASE-STUDY-CKS-17MAY.md) if you want the full session log + hallazgos.

## How it works

```
You type prompt
      │
      ▼
UserPromptSubmit hook  ──►  Router classifies cluster
      │                         │
      │                         ├─ keyword match (fast path)
      │                         ├─ Gemini Flash semantic (if API key)
      │                         └─ FAISS embeddings (optional fallback)
      │
      ▼
Loads relevant SKILL.md  ──►  Injects content into Claude's reminder
      │
      ▼
Claude proceeds with the skill protocol automatically
(no Skill tool call appears in the chat)
```

For tool calls (`Bash`, `Edit`, `Write`, `Agent`), the `PreToolUse` hook re-classifies based on `tool_input.file_path` / `tool_input.command` / `tool_name` and applies the same logic — including the gate when configured.

## Configuration

### Global registry — `clusters.yaml`

The base catalog of clusters. Each cluster declares:

```yaml
my_cluster:
  description: "What this cluster covers"
  triggers_natural:
    - "phrases the user would say"
    - "other natural triggers"
  paths:                          # optional — PreToolUse path match
    - "src/components/**/*.tsx"
  commands:                       # optional — PreToolUse command match
    - "git commit"
    - "git push"
  tool_match:                     # optional — tool_name + input criteria
    - { tool: Agent, run_in_background: true }
  skills:
    - my-namespace:my-skill
  confidence_threshold: 0.7       # min Gemini confidence to activate
  gate: false                     # if true: warn → block on 2nd call
  gate_reminder: |                # optional multi-line text injected with skill list
    Remember: this domain requires explicit skill invocation.
```

See [`v2/clusters.yaml`](v2/clusters.yaml) for 20+ working examples.

### Per-repo extensions — `clusters.local.yaml`

Drop `<repo>/.claude/skill-router/clusters.local.yaml` and the router auto-merges it (walking from `cwd` upward, stopping at `$HOME`). Same `id` → replaces; new `id` → appends.

### Environment variables

| Variable | Effect |
|---|---|
| `SKILL_ROUTER_OFF=1` | Bypass router completely |
| `SKILL_ROUTER_VERSION=1` | Fall back to V1 (regex-only, no semantic) |
| `SKILL_ROUTER_NO_CONTEXT_INJECTION=1` | Suggest skill names only, don't inject `SKILL.md` content |
| `GEMINI_API_KEY=...` | Enable Gemini Flash semantic classification (also picks up `.env`) |

### Bypass tokens (per prompt)

| Token | Effect |
|---|---|
| `[raw]` (at start) | Total bypass for this prompt |
| `[no-skill]` | Mark turn as not needing a skill |
| `[force-tool]` | Allow direct tool use; cluster gate downgraded to warning |
| `[skip-cluster:NAME]` | Ignore activation of one specific cluster |

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full technical breakdown — components, flow, schema, extension points, and tests.

## Acknowledgments

Inspired by [`xixu-me/skills@openclaw-secure-linux-cloud`](https://github.com/xixu-me/skills) and the broader openclaw community pushing the limits of what a personal AI gateway can do.

Built with [Claude Code](https://docs.claude.com/claude-code) by Anthropic.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

PRs welcome. Open an issue first to discuss substantial changes. See [`CONTRIBUTING.md`](CONTRIBUTING.md) if present, otherwise standard GitHub flow:

1. Fork
2. Branch (`git checkout -b feat/your-feature`)
3. Test (`pytest v2/tests/ v3-niveldios/*/tests/`)
4. PR with description

## Built by

David Utrero ([@David-CKS](https://github.com/David-CKS)) · Madrid 🇪🇸 · 17 may 2026
