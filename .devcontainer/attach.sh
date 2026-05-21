#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional first argument: worktree name. Forwarded as `claude --worktree <name>`.
WORKTREE_NAME="${1:-}"

# Fast path — assumes start.sh has already brought the container up and
# installed the devcontainer CLI locally. Errors out cleanly if either is missing.
DEVCONTAINER_BIN="$PROJECT_DIR/node_modules/.bin/devcontainer"
if [[ ! -x "$DEVCONTAINER_BIN" ]]; then
    echo "ERROR: devcontainer CLI not found at $DEVCONTAINER_BIN. Run ./start.sh first." >&2
    exit 1
fi

if ! "$DEVCONTAINER_BIN" exec --workspace-folder "$PROJECT_DIR" true >/dev/null 2>&1; then
    echo "ERROR: dev container is not running. Run ./start.sh to build and start it." >&2
    exit 1
fi

if [[ -n "$WORKTREE_NAME" ]]; then
    echo "==> Attaching Claude (worktree: $WORKTREE_NAME)..."
    exec "$DEVCONTAINER_BIN" exec --workspace-folder "$PROJECT_DIR" \
        zsh -c "claude --dangerously-skip-permissions --worktree $WORKTREE_NAME"
else
    echo "==> Attaching Claude..."
    exec "$DEVCONTAINER_BIN" exec --workspace-folder "$PROJECT_DIR" \
        zsh -c 'claude --dangerously-skip-permissions'
fi
