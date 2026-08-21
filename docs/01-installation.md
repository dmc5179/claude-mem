# claude-mem: Installation and Session Ingestion on Fedora 43

This document covers system dependency setup, native installation of **claude-mem**, and manual ingestion of existing Claude CLI session history.

---

## 1. System Dependencies (Fedora 43)

```bash
sudo dnf update -y

sudo dnf install -y \
    nodejs \
    npm \
    sqlite \
    sqlite-devel \
    gcc \
    gcc-c++ \
    git
```

### Install Bun Runtime

claude-mem relies on Bun for its background memory worker and SQLite handler.

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
bun --version
```

---

## 2. Installing claude-mem

claude-mem captures real-time observations (tool usage, code edits, and context compaction) and indexes them into a specialized SQLite database with hybrid FTS5 search.

```bash
npx claude-mem install
```

Alternatively, install it directly inside Claude Code:
```bash
claude
# inside Claude Code terminal:
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
```

After installation, the plugin lives at `~/.claude/plugins/claude-mem/` and the database at `~/.claude-mem/claude-mem.db`.

---

## 3. Ingesting Existing Claude CLI Sessions

Existing sessions live in `~/.claude/projects/*/` as raw `.jsonl` transcripts.

### Option A: Worker Catch-up

Starting the claude-mem worker service processes both new and existing session transcripts:

```bash
bun run ~/.claude/plugins/claude-mem/plugin/scripts/worker-service.cjs start
```

The worker will scan existing sessions on startup, then continue watching for new ones. Stop it with `Ctrl-C` after the initial catch-up completes if you only want a one-shot import.

### Option B: Standalone Python Import

A standalone Python import script reads `.jsonl` transcripts and writes observations directly to the claude-mem SQLite database:

```bash
python3 import_sessions.py
```

This is useful when Bun or the plugin directory are unavailable, or when running outside a container.

---

## 4. Automation and Continuous Ingestion

### Option A: Shell Alias (Light Use)

Add a sync trigger to your `~/.bashrc` or `~/.zshrc` that starts the worker briefly after each Claude session:

```bash
alias claude='claude; bun run ~/.claude/plugins/claude-mem/plugin/scripts/worker-service.cjs start >/dev/null 2>&1 &'
```

### Option B: Containerized Systemd Service (Recommended)

See [03-containerized-deployment.md](03-containerized-deployment.md) for running claude-mem as a Podman Quadlet with continuous observation extraction.
