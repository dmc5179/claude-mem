# claude-mem — root cause analysis and resolution

**Investigated:** 2026-10-04
**Status:** resolved. Root causes identified and fixed. Migrated from the
containerized deployment to a native Claude Code plugin install.

Supersedes the initial debug notes captured from a session in
`/home/danclark/workspace/redhat-research`, which correctly established the
symptoms but did not identify the cause.

---

## Summary

Two reported symptoms — "search returns nothing" and "nothing captured since
Aug 20" — turned out to be **four separate defects**, plus one structural
problem that made the containerized design unworkable for capture.

| # | Defect | Effect |
|---|--------|--------|
| 1 | Containerfile set `CLAUDE_MEM_DB_PATH`; claude-mem reads `CLAUDE_MEM_DATA_DIR` | Every run used a throwaway DB in `/root/.claude-mem` |
| 2 | DB schema written by `import_sessions.py`, not by claude-mem | Worker init crashed: `no such column: memory_session_id` |
| 3 | No capture hooks ever installed | Nothing recorded after the single Aug 20 import |
| 4 | `worker-service.cjs start` forks and exits; unit had `Restart=always` | 50,645 restarts over six weeks |
| 5 | claude-mem hooks are host-native and require the `claude` CLI | A container can never capture, regardless of config |

---

## The "Aug 20 cutoff" was not a setting

`~/.claude-mem/claude-mem.db` had mtime **Aug 20 14:41** — the one and only
time `podman run ... ingest` was executed. That mode runs
`import_sessions.py`, a one-shot bulk import with no watch mode. It imported
everything that existed at that moment and exited.

Nothing was ever capturing continuously. `grep -c claude-mem
~/.claude/settings.json` returned `0`; claude-mem hooks had never been
installed. The "cutoff" is simply the high-water mark of a manual import.

---

## Defect 1 — wrong environment variable

`Containerfile` set:

```
ENV CLAUDE_MEM_DB_PATH=/data/claude-mem/claude-mem.db
ENV CLAUDE_MEM_LOG_DIR=/data/claude-mem/logs
```

claude-mem 13.x reads **neither**. It resolves `CLAUDE_MEM_DATA_DIR`, falling
back to `$HOME/.claude-mem`. In the container `$HOME=/root`, so every
invocation logged:

```
[SETTINGS] Created settings file with defaults: /root/.claude-mem/settings.json
```

and created a **fresh empty database inside the ephemeral container**, which
`--rm` then discarded. The mounted 62 MB database was never opened. This alone
accounts for every "No results found" and the empty `list_corpora()`.

Verified by shelling into the image: with `CLAUDE_MEM_DATA_DIR` set, the
mounted volume is used and `/root/.claude-mem` is never created.

---

## Defect 2 — incompatible schema

With the path corrected, the worker reached the real database and then failed:

```
[ERROR] [SYSTEM] Background initialization failed no such column: memory_session_id
```

`import_sessions.py` invented its own 7-column `observations` table.
claude-mem 13.x creates ~30 tables (`user_prompts`, `tool_uses`,
`session_summaries`, `sync_*`, `token_df`, …). The migration cannot bridge
the two. Background init aborts, the worker never reports ready, and every
query returns HTTP 503 → "No results found".

The stored `type` values (`prompt`, `response`, `system`, `queue-operation`)
are also not what the tool API consumes (`decision`, `bugfix`, `feature`, …),
because v13 observations are LLM-extracted summaries, not raw transcript rows.

**This database is not migratable.** See "The archive" below.

---

## Defect 3 — the MCP server is not a SQLite client

`search`, `timeline`, and `get_observations` are HTTP calls to a worker daemon
on `127.0.0.1`. Running the MCP server as `podman run --rm -i` per invocation
cold-starts a worker that dies seconds later:

```
[ERROR] Spawn-lock holder never produced a live worker before readiness timed out
[ERROR] Worker not available — MCP tools that require the worker will fail
```

This is why the direct `sqlite3` FTS query returned 2,607 matches while the
MCP server returned nothing. The two were never reading the same thing.

---

## Defect 4 — a 50,645-iteration crash loop

`worker-service.cjs start` is a **hook handler**, not a daemon. It forks the
real worker, prints `{"continue":true,"status":"ready","suppressOutput":true}`
and exits 0. The forked child died with the container; `Restart=always` fired
again 15 seconds later. Running since Aug 20:

```
NRestarts=50645
```

`claude-mem-resume.service` also targeted `claude-mem-worker-container.service`,
which never existed — a `foo.container` quadlet generates `foo.service`.

The long-running foreground process is `worker-service.cjs --daemon`.

---

## Defect 5 — the container cannot capture, structurally

This is the finding that decided the migration. claude-mem ships as a Claude
Code **plugin**; capture happens in a `PostToolUse` hook whose command is
hardcoded to a host path:

```
$HOME/.claude/plugins/cache/thedotmack/claude-mem/<version>/scripts/worker-service.cjs
```

executed with host `node`/`bun`. Extraction additionally shells out to the
`claude` CLI, which was not in the image:

```
[WARN] Claude CLI dependency preflight failed — Claude executable not found
```

A container cannot satisfy host-side hooks. **The containerized deployment
could never have captured anything**, no matter how the volumes were mounted.
The container was only ever viable for the read path.

---

## Resolution

Migrated to a native plugin install:

```bash
# 1. Stop the crash loop
systemctl --user disable --now claude-mem-worker.service claude-mem-resume.service
rm ~/.config/containers/systemd/claude-mem-worker.container \
   ~/.config/systemd/user/claude-mem-resume.service
systemctl --user daemon-reload

# 2. Drop the container MCP entry
claude mcp remove claude-mem -s user

# 3. Archive the old database (see below)
mv ~/.claude-mem ~/.claude-mem-archive-aug20

# 4. bun is required — there is no node fallback in bun-runner.js
curl -fsSL https://bun.sh/install | bash

# 5. Install the plugin
claude plugin marketplace add thedotmack/claude-mem
claude plugin install claude-mem@thedotmack
claude plugin update  claude-mem@thedotmack   # installs the packages it lists
```

Write `~/.claude-mem/settings.json` **before** first worker start, or
claude-mem bakes in its defaults (Chroma and Telegram both default to `true`).

Verified healthy:

```
[WORKER] Using Claude CLI v2.1.289 at /home/danclark/.local/bin/claude
[SYSTEM] Dependency preflight passed
[SYSTEM] Chroma disabled via CLAUDE_MEM_CHROMA_ENABLED=false
[DB    ] FTS5 tables created successfully
[TRANSCRIPT] Transcript watcher disabled via CLAUDE_MEM_TRANSCRIPTS_ENABLED=false
[SYSTEM] Core initialization complete (DB + search ready)
```

`claude mcp list` → `plugin:claude-mem:mcp-search … ✔ Connected`.

---

## The archive

The old database is the **only surviving copy** of most of its contents:

| | |
|---|---|
| Sessions in DB | 172 |
| Still have a `.jsonl` on disk | **3** |
| Transcript rotated away — DB is the only copy | **169** |
| Orphaned content | 14,095 rows, 31 MB, Jul 17 – Aug 20 |

Kept read-only at `~/.claude-mem-archive-aug20/claude-mem.db`, searchable via
`~/.local/bin/mem-archive` (`mem-archive -l`, `mem-archive -p <project> <query>`,
`mem-archive -s <session_id>`). Its FTS5 index is intact.

It is **not** merged into the new install. Beyond the schema gap,
`import_sessions.py` stored `str(message_dict)` — a Python repr, not JSON —
and dropped `uuid`, `parentUuid`, and `cwd`. Claude Code transcripts are a
parent-linked chain, so faithful `.jsonl` reconstruction is impossible; only
an approximation, which would risk corrupting a second database.

---

## Capture tuning

Costs of over-capturing, in order of impact:

1. **Per-session inference** — `PostToolUse` fires on every tool call and runs
   Haiku to extract observations. Continuous background usage while you work.
   Controlled by `CLAUDE_MEM_SKIP_TOOLS` and `CLAUDE_MEM_MAX_CONCURRENT_AGENTS`.
2. **Context injected at SessionStart** — `CLAUDE_MEM_CONTEXT_OBSERVATIONS`
   (default 50, range 1–200) plus `CLAUDE_MEM_CONTEXT_SESSION_COUNT`
   (default 10).
3. **Plugin surface** — the 22 bundled skills cost ~1,647 tokens in every
   session, independent of memory content.
4. **Storage** — least significant. 62 MB for six weeks of raw transcripts;
   extracted observations are far smaller.

Conservative settings applied: navigation tools (`Read`, `Grep`, `Glob`,
`BashOutput`, `KillShell`) added to `SKIP_TOOLS`; `CONTEXT_OBSERVATIONS=15`;
`CONTEXT_SESSION_COUNT=5`; `MAX_CONCURRENT_AGENTS=1`; Chroma, Telegram,
semantic inject and the transcript watcher all disabled.

Capture is **forward-only**. The 88 transcripts already in
`~/.claude/projects` were not backfilled; the transcript watcher stays off
until `~/.claude-mem/transcript-watch.json` is created deliberately.

---

## Repository fixes applied

- `Containerfile` — `CLAUDE_MEM_DB_PATH` → `CLAUDE_MEM_DATA_DIR`
- `entrypoint.sh` — `worker` mode now runs `--daemon`, not `start`
- `quadlets/` — corrected `claude-mem-worker-container.service` references and
  added `Environment=CLAUDE_MEM_DATA_DIR`

These make the container correct for the **read path**. They do not make it
capable of capture — see defect 5.
