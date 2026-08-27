# claude-mem: session memory extraction and MCP server
# https://github.com/thedotmack/claude-mem
#
# Base: UBI 9 (ubi:latest builder, ubi-minimal:latest runtime)
#
# On subscribed RHEL/Fedora hosts, Podman bind-mounts host entitlement
# certs into containers, causing the subscription-manager dnf plugin to
# enable RHEL CDN repos alongside the public UBI repos. This breaks
# builds when the certs aren't valid inside the container context.
# Fix: --disableplugin=subscription-manager on all dnf/microdnf calls.
#
# Modes (set via CMD or override at runtime):
#   mcp       — stdio MCP server for Claude Code integration
#   ingest    — one-shot Python import of existing ~/.claude session history
#   worker    — background worker for observation generation
#   server    — HTTP API server (port 37877)

FROM registry.access.redhat.com/ubi9/ubi:latest AS builder

ARG BUN_VERSION=1.3.12
ARG UV_VERSION=0.11.7

RUN dnf --disableplugin=subscription-manager \
        module enable nodejs:20 -y && \
    dnf --disableplugin=subscription-manager \
        install -y --setopt=install_weak_deps=False \
        nodejs npm git gcc gcc-c++ make unzip \
        sqlite sqlite-devel ca-certificates && \
    dnf clean all

RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "bun-v${BUN_VERSION}"

RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | \
    UV_INSTALL_DIR=/usr/local/bin sh

ARG CLAUDE_MEM_VERSION=main
RUN git clone --depth 1 --branch "${CLAUDE_MEM_VERSION}" \
    https://github.com/thedotmack/claude-mem.git /build/claude-mem

WORKDIR /build/claude-mem
RUN npm install --omit=dev || npm install

# --- runtime stage ---
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf --disableplugin=subscription-manager \
        install -y sqlite python3 && \
    microdnf clean all

COPY --from=builder /usr/local/bin/bun /usr/local/bin/bun
COPY --from=builder /usr/local/bin/uv /usr/local/bin/uv
COPY --from=builder /usr/local/bin/uvx /usr/local/bin/uvx
COPY --from=builder /build/claude-mem /opt/claude-mem

WORKDIR /opt/claude-mem

COPY import_sessions.py /opt/claude-mem/import_sessions.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV CLAUDE_DIR=/data/claude
ENV CLAUDE_MEM_DB_PATH=/data/claude-mem/claude-mem.db
ENV CLAUDE_MEM_LOG_DIR=/data/claude-mem/logs

EXPOSE 37877

VOLUME ["/data/claude", "/data/claude-mem"]

ENTRYPOINT ["entrypoint.sh"]
CMD ["mcp"]
