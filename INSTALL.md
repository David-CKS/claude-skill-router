# Install Guide — claude-skill-router

End-to-end install, verify, configure, and troubleshoot.

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Claude Code | latest | https://docs.claude.com/claude-code |
| Python | 3.10+ | `python3 --version` |
| Node.js + npx | 18+ | Required for `npx skills add ...` |
| `pyyaml` | any | `pip install pyyaml` |

Optional for advanced features:

| Requirement | Used for |
|---|---|
| `sentence-transformers` + `faiss-cpu` | Embeddings fallback (semantic search across SKILL.md) |
| `fastapi`, `uvicorn[standard]`, `jinja2`, `jsonschema`, `python-multipart` | Web dashboard |
| `rapidfuzz` | Auto-evolution (gap query grouping) |
| Gemini API key (`GEMINI_API_KEY`) | LLM semantic classification (free tier suffices) |

## Quick install (recommended)

```bash
# 1. Pull the skill bundle from the marketplace
npx skills add David-CKS/claude-skill-router@router -g -y

# 2. Run the install script (idempotent — safe to re-run)
bash ~/.agents/skills/router/scripts/install.sh

# 3. Restart Claude Code (or simply open a new session)
```

The install script:
- Detects whether you have `~/.claude/settings.json` or `~/.claude/settings.local.json`.
- Adds `UserPromptSubmit` + `PreToolUse` hooks pointing at the router (skips if already present).
- Creates initial state files under `~/.claude/skill-router/v2/`.
- Verifies `python3` + `pyyaml` are importable.
- Reports final status, including any optional features detected.

## Manual install (for hackers)

If you'd rather wire it up yourself:

```bash
# 1. Clone into ~/.claude/
git clone https://github.com/David-CKS/claude-skill-router.git ~/.claude/skill-router

# 2. Install Python dependencies (minimum)
pip install pyyaml

# 3. Add hooks to ~/.claude/settings.json (merge with existing config)
```

Hooks block to merge into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skill-router/v2/trigger_v2.py --hook UserPromptSubmit"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skill-router/v2/trigger_v2.py --hook PreToolUse"
          }
        ]
      }
    ]
  }
}
```

Make `trigger_v2.py` executable: `chmod +x ~/.claude/skill-router/v2/trigger_v2.py`.

## Verify install

```bash
# Status command — shows clusters loaded, API key detected, sources, settings
python3 ~/.claude/skill-router/v2/trigger_v2.py --status

# Smoke test — should print JSON with a cluster matched
echo '{"prompt":"git commit and push","session_id":"test","cwd":"/tmp"}' | \
  python3 ~/.claude/skill-router/v2/trigger_v2.py --hook UserPromptSubmit
```

If you see `clusters.yaml` loaded and a non-empty `clusters_activated` entry — you're good.

## Configure clusters

Start from the example registry:

```bash
cp ~/.claude/skill-router/v2/clusters.example.yaml ~/.claude/skill-router/v2/clusters.yaml
```

Edit `clusters.yaml` to add your own clusters. The format is documented in [README.md → Configuration](README.md#configuration). No restart needed — the router reads the YAML on each hook invocation.

For per-project clusters, drop a `clusters.local.yaml` in any repo at:

```
<your-repo>/.claude/skill-router/clusters.local.yaml
```

The router walks from `cwd` upward (capped at `$HOME`) and merges the first one it finds.

## Optional features

### Audit log (JSONL)

Auto-activates when `v3-niveldios/audit/` is present. Logs every routing decision to `~/.claude/skill-router/v3-niveldios/audit/log/YYYY-MM-DD.jsonl` with:
- Rotation: 1 file per day
- Retention: 90 days (auto-prune on each write)
- PII scrub: JWT, Bearer, `sk-*`, `ghp_*`, `vcp_*`, `github_pat_*`, `AIza*`, Slack `xox*`, `api_key=...`

Query with `router-stats`:

```bash
~/.claude/skill-router/v3-niveldios/audit/bin/router-stats summary --days 7
~/.claude/skill-router/v3-niveldios/audit/bin/router-stats skills --days 30
~/.claude/skill-router/v3-niveldios/audit/bin/router-stats gaps --days 14
```

### Embeddings fallback

For semantic search across `SKILL.md` files (when keyword + Gemini both miss):

```bash
pip install sentence-transformers faiss-cpu
python3 ~/.claude/skill-router/v3-niveldios/embeddings/build_index.py
```

The router auto-detects the index and uses it as the third detection layer.

### Web dashboard

```bash
# Start
bash ~/.claude/skill-router/v3-niveldios/dashboard/bin/router-dashboard start

# Open
open http://127.0.0.1:9300

# Manage
router-dashboard status     # health check + curl
router-dashboard logs       # tail -f uvicorn log
router-dashboard test       # 7/7 pytest suite
router-dashboard stop
router-dashboard restart
```

Views: overview cards, cluster table, cluster detail + YAML editor with server-side validation, audit log viewer, charts (line + bar).

### Auto-evolution weekly report

Detect ghost skills, cold clusters, gap queries. Crontab example (Sunday 21:00 UTC):

```bash
crontab -e
```

```cron
0 21 * * 0 ~/.claude/skill-router/v3-niveldios/evolve/bin/router-evolve.sh \
  >> ~/.claude/skill-router/v3-niveldios/evolve/cron.log 2>&1
```

For Telegram delivery, set `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` and add `--send-telegram`.

Reports persist to `evolve/reports/YYYY-WNN.md`.

## Uninstall

```bash
# Remove the skill bundle
npx skills remove David-CKS/claude-skill-router

# Remove the hooks from ~/.claude/settings.json (manual)
# Edit the file and delete the entries pointing at .../skill-router/v2/trigger_v2.py
```

Optionally delete state and logs:

```bash
rm -rf ~/.claude/skill-router/
```

## Troubleshooting

### Gate blocks `Bash` (or another tool) and won't release

Reset the grace counter:

```bash
rm -f ~/.claude/skill-router/v2/state/gate_grace.json
```

Or bypass for one prompt: prepend `[force-tool]` to your message.

### `SKILL.md` content isn't being injected

Check the env var: `echo $SKILL_ROUTER_NO_CONTEXT_INJECTION` — if it's `1`, unset it. Also confirm `clusters_activated` is non-empty in `--status` and that the matched skill resolves to a real path (see `--status` output for `marketplace` paths scanned).

### Router not running at all

```bash
# Confirm hooks are wired
python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude/settings.json'))['hooks'], indent=2))"

# Check stderr from the hook (Claude Code prints it on errors)
# If 'No module named yaml': pip install pyyaml
```

Also check `SKILL_ROUTER_OFF` — if set to `1` the router exits early.

### Gemini classification not working

```bash
# Verify API key is detected
python3 ~/.claude/skill-router/v2/trigger_v2.py --status | grep -i gemini

# Set in .env or shell
export GEMINI_API_KEY=your_key_here
```

The router will still work with keyword + embeddings (if installed) when Gemini is absent — just less semantically accurate.

### Dashboard says `degraded`

Means `clusters.yaml` failed to parse. Check the editor at `http://127.0.0.1:9300/clusters/{id}/edit` for the offending cluster — server-side validation will tell you exactly what's wrong.

## Next steps

- Read [`ARCHITECTURE.md`](ARCHITECTURE.md) for the technical breakdown.
- Customize `clusters.yaml` for your domains.
- Run for a week, then check the auto-evolution report for ghost/gap insights.
