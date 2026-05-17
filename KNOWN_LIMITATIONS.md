# Known Limitations · claude-skill-router v1.0.0

Honest list of things the router does NOT do well yet. PRs welcome.

---

## L1 · Batch parallel Bash with gate cancels the second tool call

**Severity:** Medium · **Status:** roadmap v1.1

**Symptom:** when you launch 2+ `Bash` (or `Edit`/`Write`) tool calls in the same model turn AND the gate is active for the first one, the second tool call is cancelled with `parallel tool call errored` once the first one resolves the gate. You have to retry the second call in a separate turn.

**Why it happens:** the gate is currently evaluated per tool call. When the first `Bash` resolves the gate by invoking the required `Skill`, the second `Bash` was already dispatched and gets cancelled by the harness as a stale parallel call.

**Workaround today:** sequence the calls (one turn each), OR pass `[force-tool]` in the user prompt to bypass the gate entirely for that turn.

**Planned fix (v1.1):** evaluate the gate ONCE per turn globally. If the first tool call of the turn satisfies the gate, subsequent calls in the same turn skip gate re-evaluation. Tracked as `[issue #2](https://github.com/David-CKS/claude-skill-router/issues/2)`.

---

## L2 · Env override `SKILL_ROUTER_NO_CONTEXT_INJECTION=1` not wired to all 4 inject points

**Severity:** Low · **Status:** roadmap v1.1

**Symptom:** the helper `_should_disable_context_injection(env)` exists in `trigger_v2.py` (~line 502) but the 4 sites that compute `inject_enabled = bool(settings.get("context_injection_enabled", True))` do NOT call the helper. As a result, the env var works only if you also flip `context_injection_enabled: false` in settings.

**Workaround today:** in `settings.json` set `context_injection_enabled: false`. Or simply don't set the env var — context injection is generally desirable.

**Planned fix (v1.1):** chain `and not _should_disable_context_injection(os.environ)` to the 4 sites, with a single regression test fix to avoid breaking T1/T4/T5 of the test suite.

---

## L3 · Embeddings FAISS index not auto-built on install

**Severity:** Low · **Status:** documented workaround

**Symptom:** the embeddings semantic fallback (used when keyword/LLM confidence falls below threshold) requires a pre-built FAISS index. On a fresh install the index is empty, so the fallback returns 0 results until you run `python v3-niveldios/embeddings/build_index.py` once.

**Workaround:** documented in [INSTALL.md](INSTALL.md) under "Optional features → embeddings fallback". The provided cron entry rebuilds the index every Sunday at 04:00.

**Planned improvement (v1.2):** `scripts/install.sh` could prompt the user to build the index during setup, with sensible defaults (`sentence-transformers/all-MiniLM-L6-v2`, ~80MB download, ~2 min build for 200 skills).

---

## L4 · No Windows support tested

**Severity:** Medium · **Status:** community help wanted

**Symptom:** the router uses POSIX path conventions and `os.environ` lookups for `HOME`. Windows support has not been tested end-to-end.

**Workaround:** WSL2 should work (treat it as Linux). Native Windows PowerShell support TBD.

**Planned (v1.2):** explicit Windows path handling + PowerShell-friendly `install.ps1`. PRs welcome from Windows users.

---

## L5 · Cluster matching latency depends on Gemini Flash 2.0 availability

**Severity:** Low · **Status:** by design

**Symptom:** when keyword matching fails, the router falls back to semantic match via Gemini Flash 2.0 (~200-400ms median). If `GEMINI_API_KEY` is missing or the Gemini API is down, the router falls back to keyword-only (V1 regex), which has lower recall on natural-language prompts.

**Workaround:** set `GEMINI_API_KEY` env var (free tier 1500 req/day is generous). Router caches LLM results with 1h TTL to avoid repeated calls for similar prompts.

**By design:** no plans to move away from this — Gemini Flash gives the best speed/quality ratio for cluster classification at this scale.

---

## Reporting new issues

Found something not in this list? Open an issue:

```bash
gh issue create --repo David-CKS/claude-skill-router \
  --title "Bug: <short description>" \
  --body "Steps to reproduce + expected vs actual"
```

Or via the GitHub web UI: https://github.com/David-CKS/claude-skill-router/issues/new
