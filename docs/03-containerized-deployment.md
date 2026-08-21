# claude-mem: Containerized Deployment

Build and run claude-mem in a Podman container with user-level systemd services via Quadlets.

---

## Prerequisites

- **Podman 4.x+** (rootless mode)
- **systemd** user session

```bash
podman --version
loginctl enable-linger $USER
```

No Bun, Node.js, or other runtime dependencies are needed on the host. The container images are based on Red Hat UBI 9 (`ubi:latest` for the build stage, `ubi-minimal:latest` for the runtime stage).

### RHEL Subscription Leak on Fedora Hosts

On subscribed RHEL or Fedora hosts, Podman automatically mounts host entitlement certificates into containers via `/run/secrets/`. This causes RHEL repos (`rhel-9-for-x86_64-baseos-rpms`, `rhel-9-for-x86_64-appstream-rpms`) to appear **enabled** inside UBI containers alongside the public UBI repos, which can lead to metadata errors, timeouts, or packages resolving from RHEL instead of UBI.

The Containerfile handles this by passing `--disableplugin=subscription-manager` on all `dnf` and `microdnf` commands, which prevents the plugin from injecting RHEL repos. Only the public UBI CDN repos are used. No manual `--disablerepo`/`--enablerepo` flags are needed.

---

## 1. Building the Container Image

```bash
chmod +x build.sh
./build.sh
```

Pin to a specific release:
```bash
CLAUDE_MEM_VERSION=v1.0.0 ./build.sh
```

Force a clean rebuild:
```bash
./build.sh --no-cache
```

Verify:
```bash
podman images quay.io/danclark/claude-mem
```

### Container Modes

The entrypoint supports multiple modes:

| Mode | Command | Description |
|------|---------|-------------|
| `mcp` | `podman run --rm -i ... mcp` | stdio MCP server for Claude Code |
| `ingest` | `podman run --rm ... ingest` | One-shot Python import of existing session history |
| `worker` | `podman run -d ... worker` | Background worker for continuous observation extraction |
| `server` | `podman run -d -p 37877:37877 ... server` | HTTP API server with web viewer |
| `shell` | `podman run --rm -it ... shell` | Interactive shell for debugging |

---

## 2. Manual Ingestion of Existing Sessions

Back-fill your existing session transcripts from `~/.claude/projects/`:

```bash
mkdir -p ~/.claude-mem

podman run --rm \
    -v ~/.claude:/data/claude:ro,z \
    -v ~/.claude-mem:/data/claude-mem:z \
    quay.io/danclark/claude-mem:latest ingest
```

Verify:
```bash
sqlite3 ~/.claude-mem/claude-mem.db \
    "SELECT COUNT(*) FROM observations;"
```

### Standalone Python Fallback

If the built-in ingestion fails, use the standalone Python script:

```bash
podman run --rm \
    -v ~/.claude:/data/claude:ro,z \
    -v ~/.claude-mem:/data/claude-mem:z \
    quay.io/danclark/claude-mem:latest shell -c \
    "python3 /opt/claude-mem/import_sessions.py"
```

Or run it directly on the host:
```bash
python3 import_sessions.py
```

---

## 3. Continuous Syncing with Quadlets

Podman Quadlets are declarative `.container` files that systemd generators translate into native systemd units.

### Install the Quadlet and Resume Handler

```bash
mkdir -p ~/.config/containers/systemd/
mkdir -p ~/.config/systemd/user/

cp quadlets/claude-mem-worker.container ~/.config/containers/systemd/
cp quadlets/claude-mem-resume.service   ~/.config/systemd/user/
systemctl --user daemon-reload
```

### Enable and Start the Worker

```bash
systemctl --user enable --now claude-mem-worker claude-mem-resume
systemctl --user status claude-mem-worker
```

Check logs:
```bash
journalctl --user -u claude-mem-worker -f
```

### Suspend and Resume Handling

When the system suspends, the container process freezes with the kernel and resumes afterward — it does not crash, so `Restart=on-failure` would not trigger. However, internal state (timers, connections, worker queues) can be stale after resume.

The `claude-mem-resume.service` monitors D-Bus for logind's `PrepareForSleep(false)` signal. When the system wakes, it waits 2 seconds for the network to stabilize, then restarts the worker container. This is necessary because systemd's `sleep.target` is system-level only — user services cannot bind to it directly.

Verify the resume handler is running:
```bash
systemctl --user status claude-mem-resume
```

Test manually (simulate what happens on resume):
```bash
systemctl --user restart claude-mem-worker
```

### MCP Server Quadlet (Reference)

The `quadlets/claude-mem-mcp.container` file is provided as a reference for the on-demand MCP server container spec. For Claude Code integration, configure the MCP server in `~/.claude.json` as described in [02-mcp-server.md](02-mcp-server.md).

---

## 4. MCP Integration (Containerized)

See [02-mcp-server.md](02-mcp-server.md) for full MCP configuration. The containerized config uses Podman as the MCP command:

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

---

## 5. Managing the Service

```bash
systemctl --user stop claude-mem-worker
systemctl --user restart claude-mem-worker
systemctl --user disable claude-mem-worker
systemctl --user list-units 'claude-mem-*'
```

---

## 6. Rebuilding and Updating

```bash
./build.sh --no-cache
systemctl --user restart claude-mem-worker
```

With `AutoUpdate=local` in the quadlet (already configured):
```bash
podman auto-update
```

---

## 7. Directory Layout

| Path | Purpose | Container Mount |
|------|---------|-----------------|
| `~/.claude/` | Claude CLI sessions and config | `/data/claude` (read-only) |
| `~/.claude-mem/` | SQLite DB and logs | `/data/claude-mem` (read-write) |
| `~/.config/containers/systemd/` | Quadlet files | — (host only) |

---

## 8. Troubleshooting

### SELinux Denials

The `:z` suffix on volume flags handles relabeling. If problems persist:
```bash
sudo ausearch -m AVC -ts recent
```

### Container Fails to Start

```bash
podman run --rm -it \
    -v ~/.claude:/data/claude:ro,z \
    -v ~/.claude-mem:/data/claude-mem:z \
    quay.io/danclark/claude-mem:latest shell
```

### Quadlet Unit Not Generated

```bash
ls -la ~/.config/containers/systemd/
systemctl --user daemon-reload
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun 2>&1
```
