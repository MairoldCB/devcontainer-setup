#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional first argument: worktree name. Forwarded as `claude --worktree <name>`.
WORKTREE_NAME="${1:-}"

# Fast path — assumes start.sh has already brought the container up and
# installed the devcontainer CLI. Errors out cleanly if either is missing.
if ! command -v devcontainer >/dev/null 2>&1; then
    echo "ERROR: devcontainer CLI not found. Run ./start.sh first." >&2
    exit 1
fi

if ! devcontainer exec --workspace-folder "$PROJECT_DIR" true >/dev/null 2>&1; then
    echo "ERROR: dev container is not running. Run ./start.sh to build and start it." >&2
    exit 1
fi

if [[ -n "$WORKTREE_NAME" ]]; then
    echo "==> Attaching Claude (worktree: $WORKTREE_NAME)..."
    exec devcontainer exec --workspace-folder "$PROJECT_DIR" \
        zsh -c "claude --dangerously-skip-permissions --worktree $WORKTREE_NAME"
else
    echo "==> Attaching Claude..."
    exec devcontainer exec --workspace-folder "$PROJECT_DIR" \
        zsh -c 'claude --dangerously-skip-permissions'
fi
