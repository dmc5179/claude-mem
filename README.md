# claude-mem (Containerized)

> # ⚠️ DEPRECATED — do not deploy this
>
> **This container cannot do the job it was built for.** Use the native
> Claude Code plugin instead:
>
> ```bash
> curl -fsSL https://bun.sh/install | bash        # required; no node fallback
> claude plugin marketplace add thedotmack/claude-mem
> claude plugin install claude-mem@thedotmack
> claude plugin update  claude-mem@thedotmack
> ```
>
> **Why.** Three independent blockers, none of them fixable by configuration:
>
> - **Capture is host-side.** claude-mem records via a Claude Code
>   `PostToolUse` hook that runs on the host, and extraction shells out to the
>   `claude` CLI, which is not in this image. The `worker` and `server` modes
>   start cleanly and then never produce an observation.
> - **`mcp` mode is not a SQLite client.** It is an HTTP client to a worker on
>   `127.0.0.1`. A per-invocation `podman run --rm -i … mcp` lands in a
>   different network namespace from the worker container, cold-starts its own
>   worker, and times out. Co-locating them in a pod would then put two workers
>   on one SQLite file.
> - **`ingest` writes an incompatible schema.** `import_sessions.py` creates a
>   7-column `observations` table; claude-mem 13.x expects ~30 tables and
>   aborts background init with `no such column: memory_session_id`. The two
>   are not migratable.
>
> The repository is kept for the root cause analysis in
> [initial-debug.md](initial-debug.md) and because a multi-machine or
> bun-free deployment could become viable if upstream ever decouples
> extraction from a local `claude` CLI. The fixes in the current commits make
> the image *correct* — they do not make it *useful*.

Containerized deployment of [claude-mem](https://github.com/thedotmack/claude-mem) for extracting, indexing, and searching observations from Claude CLI sessions.

claude-mem captures real-time observations (tool usage, code edits, context compaction) and indexes them into a SQLite database with FTS5 search. It exposes an MCP server that Claude Code can call during interactive sessions to retrieve past project context.

## Quick Start

```bash
# Build the image
chmod +x build.sh && ./build.sh

# One-shot ingestion of existing sessions
mkdir -p ~/.claude-mem
podman run --rm \
    -v ~/.claude:/data/claude:ro,z \
    -v ~/.claude-mem:/data/claude-mem:z \
    quay.io/danclark/claude-mem:latest ingest

# Enable continuous syncing via Quadlet
mkdir -p ~/.config/containers/systemd/
cp quadlets/claude-mem-worker.container ~/.config/containers/systemd/
cp quadlets/claude-mem-resume.service   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user start claude-mem-worker
systemctl --user enable --now claude-mem-resume
```

```
jq --arg user "$USER" '.mcpServers["claude-mem"] = {
  "command": "podman",
  "args": ["run", "--rm", "-i", "-v", "/home/\($user)/.claude:/data/claude:ro,z", "-v", "/home/\($user)/.claude-mem:/data/claude-mem:z", "quay.io/danclark/claude-mem:latest", "mcp"]
}' ~/.claude.json > ~/.claude.json.tmp && mv ~/.claude.json.tmp ~/.claude.json
```


## Documentation

| Guide | Description |
|-------|-------------|
| [docs/01-installation.md](docs/01-installation.md) | Native (non-containerized) installation and ingestion |
| [docs/02-mcp-server.md](docs/02-mcp-server.md) | MCP server configuration for Claude Code |
| [docs/03-containerized-deployment.md](docs/03-containerized-deployment.md) | Podman container, Quadlets, and automated syncing |

## Layout

```
claude-mem/
├── Containerfile          # Multi-stage UBI 9 build (ubi:latest builder, ubi-minimal:latest runtime)
├── entrypoint.sh          # Mode dispatcher: mcp, ingest, worker, server, shell
├── build.sh               # Podman build wrapper
├── import_sessions.py     # Standalone Python fallback ingestion
├── docs/
│   ├── 01-installation.md
│   ├── 02-mcp-server.md
│   └── 03-containerized-deployment.md
└── quadlets/
    ├── claude-mem-mcp.container     # On-demand MCP server (stdio)
    ├── claude-mem-worker.container  # Background observation worker
    └── claude-mem-resume.service    # Restart worker on resume from suspend
```
