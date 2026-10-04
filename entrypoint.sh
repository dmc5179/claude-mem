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
        exec bun run /opt/claude-mem/plugin/scripts/worker-service.cjs start "$@"
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
