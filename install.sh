#!/bin/bash
set -euo pipefail

# Downloads the .devcontainer/ template from MairoldCB/devcontainer-setup
# into the current directory. Intended to be run from your project root.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MairoldCB/devcontainer-setup/main/install.sh | bash
# or, after cloning, just:
#   ./install.sh

REPO_RAW="https://raw.githubusercontent.com/MairoldCB/devcontainer-setup/main"
TARGET_DIR=".devcontainer"

FILES=(
    "Dockerfile"
    "allowed-domains.conf"
    "attach.sh"
    "devcontainer.json"
    "docker-compose.yml"
    "init-firewall.sh"
    "start.sh"
)

if [[ -e "$TARGET_DIR" ]]; then
    echo "ERROR: $TARGET_DIR already exists in $(pwd)." >&2
    echo "Remove or rename it first, then re-run this installer." >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required but was not found on PATH." >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"

for file in "${FILES[@]}"; do
    echo "==> Downloading $file"
    curl -fsSL "$REPO_RAW/$TARGET_DIR/$file" -o "$TARGET_DIR/$file"
done

chmod +x "$TARGET_DIR/start.sh" "$TARGET_DIR/attach.sh" "$TARGET_DIR/init-firewall.sh"

echo "Now run .devcontainer/start.sh script to get started"