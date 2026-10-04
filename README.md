# claude-mem (Containerized)

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
