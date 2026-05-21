#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional first argument: worktree name. Forwarded as `claude --worktree <name>`,
WORKTREE_NAME="${1:-}"

# Install the Dev Containers CLI on demand.
# Official distribution channel is npm — see https://github.com/devcontainers/cli
if ! command -v devcontainer >/dev/null 2>&1; then
    echo "devcontainer CLI not found — installing @devcontainers/cli globally via npm..."
    if ! command -v npm >/dev/null 2>&1; then
        echo "ERROR: npm is required to install @devcontainers/cli but was not found on PATH." >&2
        echo "Install Node.js (https://nodejs.org) and re-run this script." >&2
        exit 1
    fi
    npm install -g @devcontainers/cli
fi

# `devcontainer up` builds the image, starts the compose stack, applies the
# features declared in devcontainer.json, and runs the postCreateCommand
# (firewall init).
echo "==> devcontainer up"
devcontainer up --workspace-folder "$PROJECT_DIR" --log-level debug

# Attach to the running dev container as the configured remoteUser (`dev`)
# and launch Claude — optionally inside a worktree.
if [[ -n "$WORKTREE_NAME" ]]; then
    echo "==> Attaching Claude (worktree: $WORKTREE_NAME)..."
    exec devcontainer exec --workspace-folder "$PROJECT_DIR" \
        zsh -c "claude --dangerously-skip-permissions --worktree $WORKTREE_NAME"
else
    echo "==> Attaching Claude..."
    exec devcontainer exec --workspace-folder "$PROJECT_DIR" \
        zsh -c 'claude --dangerously-skip-permissions'
fi
