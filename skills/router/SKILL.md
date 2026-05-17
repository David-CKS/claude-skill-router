---
name: claude-skill-router
description: Use when installing, configuring, troubleshooting, or extending a smart skill router for Claude Code that auto-detects relevant skills from prompts and tool calls, injects SKILL.md content into the context reminder, and optionally gates Bash/Edit/Write/Agent calls. Use when skills are going ghost (suggested but never invoked), when manual Skill tool calls are cluttering the chat, when adding cluster definitions in clusters.yaml, when wiring UserPromptSubmit and PreToolUse hooks in settings.json, or when bypassing the router with tokens like [raw], [no-skill], [force-tool], [skip-cluster].
---

# claude-skill-router

## Overview

Smart skill router for Claude Code. Detects which skill applies to your prompt or tool call, injects the relevant `SKILL.md` content into Claude's context, and optionally enforces invocation via a gate with grace period.

Eliminates the noise of manual `Skill("X")` tool calls in chat. Replaces "model has to remember and choose" with deterministic detection + context injection.

## When to use

- Installing the router on a fresh Claude Code setup.
- Configuring a new cluster (e.g. for a project-specific skill).
- Troubleshooting: skills going ghost, gate blocking unexpectedly, `SKILL.md` not being injected.
- Adding per-repo extensions via `clusters.local.yaml`.
- Running the dashboard, audit log, or auto-evolution weekly report.

## Install

```bash
# 1. Pull from marketplace
npx skills add David-CKS/claude-skill-router@router -g -y

# 2. Wire hooks (idempotent)
bash ~/.agents/skills/router/scripts/install.sh

# 3. Restart Claude Code
```

## Quick reference

| Task | Command / file |
|---|---|
| Full README | [README.md](https://github.com/David-CKS/claude-skill-router/blob/main/README.md) |
| Install + verify | [INSTALL.md](https://github.com/David-CKS/claude-skill-router/blob/main/INSTALL.md) |
| Architecture | [ARCHITECTURE.md](https://github.com/David-CKS/claude-skill-router/blob/main/ARCHITECTURE.md) |
| Cluster examples | [v2/clusters.yaml](https://github.com/David-CKS/claude-skill-router/blob/main/v2/clusters.yaml) |
| Status check | `python3 ~/.claude/skill-router/v2/trigger_v2.py --status` |
| Reset gate | `rm -f ~/.claude/skill-router/v2/state/gate_grace.json` |
| Tail audit log | `tail -f ~/.claude/skill-router/v3-niveldios/audit/log/*.jsonl \| jq .` |
| Dashboard | `bash ~/.claude/skill-router/v3-niveldios/dashboard/bin/router-dashboard start` |

## Bypass tokens (per prompt)

| Token | Effect |
|---|---|
| `[raw]` | Skip router completely for this prompt |
| `[no-skill]` | Don't require a skill |
| `[force-tool]` | Allow direct tool use; gate becomes warning only |
| `[skip-cluster:NAME]` | Ignore one specific cluster |

## Environment variables

| Variable | Effect |
|---|---|
| `SKILL_ROUTER_OFF=1` | Disable router |
| `SKILL_ROUTER_VERSION=1` | Fall back to V1 (regex only) |
| `SKILL_ROUTER_NO_CONTEXT_INJECTION=1` | Suggest skill names only, don't inject `SKILL.md` body |
| `GEMINI_API_KEY=...` | Enable Gemini Flash semantic classification |
