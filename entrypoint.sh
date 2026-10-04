#!/bin/bash
set -euo pipefail

MODE="${1:-mcp}"
shift 2>/dev/null || true

mkdir -p "${CLAUDE_MEM_DATA_DIR}" "${CLAUDE_MEM_DATA_DIR}/logs"

case "${MODE}" in
    mcp)
        exec bun run /opt/claude-mem/plugin/scripts/mcp-server.cjs "$@"
        ;;
    ingest)
        exec python3 /opt/claude-mem/import_sessions.py \
            --claude-dir "${CLAUDE_DIR}/projects" \
            --db "${CLAUDE_MEM_DB_PATH}" "$@"
        ;;
    worker)
        # `start` is a hook handler: it forks the real daemon, prints a JSON
        # ack and exits 0. Under a systemd unit with Restart=always that forks
        # a child that dies with the container and restarts forever (this
        # deployment reached 50,645 restarts before it was caught). `--daemon`
        # is the long-running foreground process systemd should supervise.
        exec bun run /opt/claude-mem/plugin/scripts/worker-service.cjs --daemon "$@"
        ;;
    server)
        exec bun run /opt/claude-mem/plugin/scripts/server-service.cjs "$@"
        ;;
    shell)
        exec /bin/bash "$@"
        ;;
    *)
        echo "Usage: entrypoint.sh {mcp|ingest|worker|server|shell}" >&2
        exit 1
        ;;
esac
