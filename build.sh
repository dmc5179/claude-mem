#!/bin/bash
# Build the claude-mem container image on UBI 9.
#
# Usage:
#   ./build.sh                     # build with defaults
#   ./build.sh --no-cache          # force full rebuild
#   CLAUDE_MEM_VERSION=v1.0.0 ./build.sh  # pin to a release tag
#   BUN_VERSION=1.4.0 ./build.sh          # override Bun version
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-localhost/claude-mem}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CLAUDE_MEM_VERSION="${CLAUDE_MEM_VERSION:-main}"
BUN_VERSION="${BUN_VERSION:-1.3.12}"
UV_VERSION="${UV_VERSION:-0.11.7}"

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} (claude-mem@${CLAUDE_MEM_VERSION})"
echo "  Base: UBI 9 (ubi:latest builder, ubi-minimal:latest runtime)"
echo "  Bun: ${BUN_VERSION}, uv: ${UV_VERSION}"

podman build \
    --build-arg "CLAUDE_MEM_VERSION=${CLAUDE_MEM_VERSION}" \
    --build-arg "BUN_VERSION=${BUN_VERSION}" \
    --build-arg "UV_VERSION=${UV_VERSION}" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    -f "${SCRIPT_DIR}/Containerfile" \
    "${SCRIPT_DIR}" \
    "$@"

echo ""
echo "Done. Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Quick test:"
echo "  podman run --rm ${IMAGE_NAME}:${IMAGE_TAG} mcp --help"
