# Architecture — claude-skill-router

Technical breakdown of components, flow, schemas, and extension points.

## Components

```
~/.claude/skill-router/
├── v2/                              # Core router
│   ├── trigger_v2.py                # Hook entry — UserPromptSubmit / PreToolUse / --status
│   ├── clusters.yaml                # Cluster registry (global)
│   ├── llm_match.py                 # Gemini Flash 2.0 client + cache
│   ├── state.py                     # Anti-spam + LLM cache + gate state
│   ├── marketplace.py               # SKILL.md discovery across ~/.claude/skills, plugins/cache
│   ├── state.json                   # Runtime state (turn counter, recent skills/clusters)
│   ├── state/gate_grace.json        # Grace counter per (session, cluster)
│   ├── log.jsonl                    # Legacy flat append-only log (V2)
│   └── tests/                       # 5 test suites
│
└── v3-niveldios/                    # Advanced features
    ├── audit/                       # Structured JSONL log with rotation + PII scrub
    │   ├── logger.py
    │   ├── stats.py
    │   ├── bin/router-stats
    │   └── log/YYYY-MM-DD.jsonl     # 1 file/day, 90d retention
    ├── embeddings/                  # FAISS + sentence-transformers fallback
    │   ├── build_index.py
    │   ├── search.py
    │   └── bench.py
    ├── evolve/                      # Auto-evolution detectors + weekly report
    │   ├── analyze.py
    │   ├── propose.py
    │   ├── bin/router-evolve.sh
    │   └── reports/YYYY-WNN.md
    └── dashboard/                   # FastAPI + HTMX + Tailwind UI
        ├── app/main.py
        ├── bin/router-dashboard
        └── tests/
```

## Flow

### UserPromptSubmit

```
1. Hook receives JSON payload via stdin:
   { "prompt": "...", "session_id": "...", "cwd": "/path" }

2. Early exits:
   - SKILL_ROUTER_OFF=1                  → bypass
   - SKILL_ROUTER_VERSION=1              → fall back to V1
   - prompt starts with [raw]            → bypass
   - is_trivial_prompt (< 3 words)       → no-op

3. Load clusters:
   - Global clusters.yaml
   - Walk from cwd up to $HOME looking for .claude/skill-router/clusters.local.yaml
   - Merge (same id replaces, new id appends)

4. Classify:
   - Keyword match against triggers_natural (fast path, confidence=1.0)
   - Gemini Flash 2.0 semantic match (if GEMINI_API_KEY, confidence per cluster)
   - FAISS embeddings fallback (if index built, threshold=0.5)

5. For each activated cluster:
   - Discover SKILL.md paths via marketplace.py
   - Load up to 3000 chars per skill
   - Build injected reminder block (skill names + content + gate_reminder)

6. Emit reminder JSON to stdout (Claude Code merges into next turn's context)

7. Append audit log entry (V2 flat + V3 audit if present)
```

### PreToolUse

```
1. Hook receives JSON payload:
   { "tool_name": "Bash" | "Edit" | "Write" | "Agent" | ...,
     "tool_input": { "command": "...", "file_path": "...", ... },
     "session_id": "..." }

2. Classify by tool_input:
   - tool_input.file_path  → match cluster.paths[] glob patterns
   - tool_input.command    → match cluster.commands[] (substring + regex)
   - tool_name + criteria  → match cluster.tool_match[] (e.g. Agent + run_in_background=true)

3. Gate logic (only if matched cluster has gate: true):
   - 1st call: warning + permissionDecision=allow (grace)
   - 2nd+ call without invoking cluster skill: permissionDecision=deny
   - Skill invoked → _grace_clear() resets counter
   - TTL: settings.gate_grace_ttl_seconds (default 300s)

4. Emit decision + optional reminder
```

## Cluster YAML schema

```yaml
my_cluster:
  description: "Single-line summary used by Gemini for semantic match"

  triggers_natural:                   # natural language phrases (keyword match)
    - "give me a campaign"
    - "growth ideas"

  paths:                              # PreToolUse — glob match against tool_input.file_path
    - "src/components/**/*.tsx"
    - "docs/decisions/ADR-*.md"

  commands:                           # PreToolUse — substring + regex against tool_input.command
    - "git commit"
    - "^gh pr (create|merge)"

  tool_match:                         # PreToolUse — tool_name + arbitrary input criteria
    - tool: Agent
      run_in_background: true

  skills:                             # Skill names exactly as they appear in SKILL.md `name:`
    - my-namespace:my-skill
    - other-namespace:other-skill

  confidence_threshold: 0.7           # Min Gemini confidence to activate (0..1)

  gate: false                         # If true: warn → block after 2nd call
  gate_reminder: |                    # Optional multi-line text injected with skill block
    Remember: this domain requires explicit skill invocation.
    Anti-patterns: don't bypass with [force-tool] unless emergency.
```

## Bypass tokens (per prompt)

Tokens are recognized at the start of the user prompt:

| Token | Effect on this turn |
|---|---|
| `[raw]` | Total bypass — no router logic runs |
| `[no-skill]` | Mark turn as `needs_skill=False`; cluster suggestions still emit but reminders are softer |
| `[force-tool]` | Allow direct tool use without skill; cluster gate downgraded from `deny` to `warning` |
| `[skip-cluster:NAME]` | Ignore activation of cluster `NAME` |

## Environment variables

| Variable | Layer | Effect |
|---|---|---|
| `SKILL_ROUTER_OFF` | Process | `=1` → full bypass |
| `SKILL_ROUTER_VERSION` | Process | `=1` → V1 fallback (regex only) |
| `SKILL_ROUTER_NO_CONTEXT_INJECTION` | Process | `=1` → suggest skill names only, don't load `SKILL.md` body |
| `GEMINI_API_KEY` | LLM | Enable Gemini Flash 2.0 semantic match |
| `CLAUDE_SESSION_ID` | Session | Used for per-session gate state when payload lacks `session_id` |

The router also auto-loads `.env` files when present in cwd or `~`.

## Detection layers (in order)

1. **Keyword match** — fastest path. Substring/exact match against `triggers_natural`. Confidence = 1.0 when hit.
2. **Gemini Flash 2.0 semantic** — only if `GEMINI_API_KEY` and keyword missed. Returns confidence per cluster; cached 1h by prompt hash.
3. **FAISS embeddings fallback** — only if index built (`embeddings/build_index.py`). Searches across `SKILL.md` content with `sentence-transformers`. Top-k with threshold 0.5.

Each layer can be disabled independently; the router degrades gracefully (e.g., no Gemini key = layers 1 + 3 only).

## Extension points

### Add a custom cluster

Edit `~/.claude/skill-router/v2/clusters.yaml` and append:

```yaml
my_cluster:
  description: "..."
  triggers_natural: ["..."]
  skills: ["my-namespace:my-skill"]
  confidence_threshold: 0.7
```

No restart needed — the router reads YAML on each hook invocation.

### Per-repo cluster overrides

Drop at:

```
<your-repo>/.claude/skill-router/clusters.local.yaml
```

The router walks from `cwd` upward (capped at `$HOME`) and merges the first one it finds. Merge rules:
- Same `id` → local wins (full replace).
- New `id` → appended to global.
- `settings.*` keys → local overrides per-key.

### Hook other languages

`trigger_v2.py` reads JSON from stdin and writes JSON to stdout. Any language that can subprocess Python works. The Claude Code hook contract is documented at https://docs.claude.com/claude-code (hooks section).

## Tests

```bash
# Core router (5 suites)
cd ~/.claude/skill-router/v2
python3 tests/test_phase1_e2e.py
python3 tests/test_router_v2.py
python3 tests/test_context_injection.py
python3 tests/test_embeddings_fallback.py
python3 tests/test_live_gemini.py     # requires GEMINI_API_KEY

# Audit (7 tests)
cd ~/.claude/skill-router/v3-niveldios/audit
./.venv/bin/pytest tests/ -v

# Evolve (16 tests)
cd ~/.claude/skill-router/v3-niveldios/evolve
./venv/bin/python -m pytest tests/ -v

# Dashboard (7 E2E + TestClient + filesystem isolation)
cd ~/.claude/skill-router/v3-niveldios/dashboard
./venv/bin/python -m pytest tests/ -q
```

Pattern: every test suite is standalone (`python3 tests/<file>.py`) AND pytest-compatible.

## Audit JSONL schema (V3)

Every routing decision logged with this shape:

```json
{
  "ts": "2026-05-17T11:00:00Z",
  "session_id": "...",
  "hook_event": "UserPromptSubmit | PreToolUse | PostToolUse",
  "prompt_excerpt": "first 200 chars, PII-scrubbed",
  "cwd": "/path",
  "clusters_activated": [{"id": "...", "confidence": 0.92, "trigger": "keyword|path|command|semantic"}],
  "skills_suggested": ["namespace:skill"],
  "skill_invoked_in_turn": "namespace:skill | null",
  "tool_name": "Bash | Edit | Write | null",
  "tool_blocked": false,
  "bypass_used": "[raw] | [force-tool] | [no-skill] | [skip-cluster:X] | null",
  "outcome": "tool_executed | tool_blocked | skill_invoked_then_tool | warning_grace | bypass_executed | no_op"
}
```

Rotation: 1 file per UTC day (`YYYY-MM-DD.jsonl`). Retention: 90 days, auto-pruned on each write. Concurrency: `fcntl.LOCK_EX` for atomic append. PII scrub: JWT, Bearer, `sk-*`, `ghp_*`, `vcp_*`, `github_pat_*`, `AIza*`, Slack `xox*`, `api_key=...`.

## Dashboard endpoints

| URL | Returns |
|---|---|
| `GET /` | Overview HTML — 4 cards + 14d chart + top clusters/skills/gaps |
| `GET /clusters` | Cluster table with stats |
| `GET /clusters/{id}` | Detail + YAML + stats + triggers + gate_reminder |
| `GET /clusters/{id}/edit` | Editor with server-side jsonschema validation |
| `POST /clusters/{id}` | Backup `.bak-<ts>` + validate + write (`200/422`) |
| `GET /skills` | Active / ghost / missing classification |
| `GET /audit` | JSONL viewer with filters (session, days, limit) |
| `GET /stats` | Aggregated charts + raw summary JSON |
| `GET /health` | Health JSON (status, version, clusters_count, last_event_ts, etc.) |
| `POST /actions/rebuild-embeddings` | Background job runner |
| `POST /actions/evolve?dry_run=true` | Triggers `router-evolve --dry-run` |

Bind: `127.0.0.1:9300` (override via `ROUTER_DASH_HOST` / `ROUTER_DASH_PORT`). No auth — localhost-only by design.

## Auto-evolution detectors

`v3-niveldios/evolve/analyze.py` implements 5 pure detectors over the audit JSONL:

| Detector | Triggers when |
|---|---|
| `detect_ghosts` | Skill suggested ≥ N times, invoked 0 times |
| `detect_cold_clusters` | Cluster activated < threshold over window |
| `detect_gap_queries` | Prompts that activated no cluster, grouped by fuzzy similarity |
| `detect_false_positive_clusters` | High activation, low invocation ratio |
| `detect_gate_friction` | Bypass tokens disproportionately used per cluster |

Output: weekly markdown report at `evolve/reports/YYYY-WNN.md` (~5 KB). Optional Telegram delivery via `TELEGRAM_BOT_TOKEN` + `--send-telegram`.

Fallback: if embeddings agent unavailable, gap query grouping uses `rapidfuzz.token_set_ratio` (zero extra config).

## Versioning + rollback

Each substantial change creates a timestamped backup:

```
~/.claude/skill-router/v2.bak-YYYY-MM-DD-HHMMSS/
```

Rollback:

```bash
cp ~/.claude/skill-router/v2.bak-<TS>/{trigger_v2.py,clusters.yaml} \
   ~/.claude/skill-router/v2/
```

## Design choices

| Decision | Rationale |
|---|---|
| Python-only core | Zero extra runtime deps; works wherever Python 3.10+ runs |
| YAML cluster registry | Human-editable; no DB required; merges trivially with `.local.yaml` |
| `SKILL.md` injection vs `Skill` tool call | Eliminates noisy tool calls in chat; deterministic context inclusion |
| Grace period gate vs immediate block | First call always succeeds (avoid friction); discipline enforced by 2nd call |
| JSONL audit log vs SQLite | Append-only; trivially `jq`-queryable; rotation by filename |
| Local dashboard vs remote service | Privacy + zero network deps; optional Traefik exposure documented but not required |
| Three detection layers | Keyword (free) → Gemini (cheap) → embeddings (heavier) — degrades gracefully |
