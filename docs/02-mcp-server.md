# claude-mem: MCP Server Configuration and Claude Code Integration

claude-mem exposes a Model Context Protocol (MCP) server with search tools that Claude Code can call during interactive sessions to retrieve past project context and decisions.

---

## 1. MCP Tools

claude-mem provides the following MCP tools:

| Tool | Description |
|------|-------------|
| `search_observations` | Full-text search across all extracted observations |
| `search_sessions` | Search by session metadata and timestamps |
| `find_by_concept` | Semantic concept-based retrieval |
| `find_by_file` | Find observations related to a specific file path |
| `find_by_type` | Filter by observation type (edit, tool_use, compaction, etc.) |
| `advanced_search` | Combined filters with FTS5 query syntax |

---

## 2. Native Configuration

Add the following to `~/.claude.json` (or `~/.claude/settings.json` under `mcpServers`):

```json
{
  "mcpServers": {
    "claude-mem": {
      "command": "bun",
      "args": [
        "run",
        "/home/YOUR_USERNAME/.claude/plugins/claude-mem/mcp/server.js"
      ],
      "env": {
        "CLAUDE_MEM_DB_PATH": "/home/YOUR_USERNAME/.claude-mem/claude-mem.db"
      }
    }
  }
}
```

Replace `YOUR_USERNAME` with your actual Fedora user.

---

## 3. Containerized Configuration

When running claude-mem in a container, configure Claude Code to invoke Podman directly:

```json
{
  "mcpServers": {
    "claude-mem": {
      "command": "podman",
      "args": [
        "run", "--rm", "-i",
        "-v", "/home/YOUR_USERNAME/.claude:/data/claude:ro,z",
        "-v", "/home/YOUR_USERNAME/.claude-mem:/data/claude-mem:z",
        "quay.io/danclark/claude-mem:latest",
        "mcp"
      ]
    }
  }
}
```

The `-i` flag keeps stdin open for the stdio-based MCP transport.

---

## 4. Validating the Connection

```bash
claude
/mcp status
```

You should see `claude-mem` listed with its search tools.

---

## 5. Querying Session Data

### Inside Claude Code (Agent Level)

Ask Claude directly during any interactive session:
> "What changes did we make to `auth.ts` last week? Check claude-mem observations."
> "Find all observations related to the database migration."

### Offline via SQLite CLI (Human Level)

```bash
sqlite3 ~/.claude-mem/claude-mem.db \
    "SELECT timestamp, project, text_content FROM observations ORDER BY id DESC LIMIT 5;"
```

---

## 6. Troubleshooting

- **Permission / Path Issues**: Ensure Bun binaries are executable (`chmod +x`).
- **FTS5 Module Missing**: Fedora's default `sqlite` package includes FTS5. If missing, reinstall `sqlite-devel`.
- **Logs**: Check runtime logs at `~/.claude-mem/logs/` if context is not updating.
