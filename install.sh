#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
SETTINGS_FILE="$PROFILES_DIR/settings.json"
DEFAULT_PROFILE="$PROFILES_DIR/default"
SHIM_SOURCE="$(cd "$(dirname "$0")" && pwd)/claude-shim.sh"
CCTX_SOURCE="$(cd "$(dirname "$0")" && pwd)/cctx.sh"
REAL_CLAUDE="$(which claude)"
LOCAL_BIN="$HOME/.local/bin"

echo "=== cctx install ==="

# Verify claude exists
if [[ -z "$REAL_CLAUDE" ]]; then
    echo "ERROR: 'claude' not found in PATH"
    exit 1
fi

# Verify jq exists
if ! command -v jq &>/dev/null; then
    echo "ERROR: 'jq' is required but not found"
    exit 1
fi

# 1. Create profiles directory
echo "Creating profiles directory..."
mkdir -p "$PROFILES_DIR"

# 2. Create profiles settings.json (if not exists)
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{ "managed_files": ["CLAUDE.md", "settings.json"] }' | jq . > "$SETTINGS_FILE"
    echo "  Created $SETTINGS_FILE"
else
    echo "  $SETTINGS_FILE already exists, skipping"
fi

# 3. Create default profile by moving managed files
echo "Creating default profile..."
mkdir -p "$DEFAULT_PROFILE"

managed_files=$(jq -r '.managed_files[]' "$SETTINGS_FILE")
while IFS= read -r file; do
    src="$CLAUDE_DIR/$file"
    dst="$DEFAULT_PROFILE/$file"

    # Skip if source doesn't exist
    if [[ ! -e "$src" && ! -L "$src" ]]; then
        echo "  WARN: $src does not exist, skipping"
        continue
    fi

    # Skip if already a symlink pointing into profiles
    if [[ -L "$src" ]]; then
        target=$(readlink "$src")
        if [[ "$target" == *"/profiles/"* ]]; then
            echo "  $file already symlinked, skipping"
            continue
        fi
    fi

    # Move file to default profile and create symlink
    if [[ ! -f "$dst" ]]; then
        cp "$src" "$dst"
        echo "  Copied $file -> default profile"
    fi
    rm -f "$src"
    ln -s "$dst" "$src"
    echo "  Symlinked $src -> $dst"
done <<< "$managed_files"

# 4. Install the claude shim
echo "Installing claude shim..."

# Back up the real claude binary
if [[ -f "$REAL_CLAUDE" && ! -L "$REAL_CLAUDE" ]]; then
    REAL_EXT=""
    [[ "$REAL_CLAUDE" == *.exe ]] && REAL_EXT=".exe"
    BACKUP="$LOCAL_BIN/claude-real${REAL_EXT}"

    if [[ ! -f "$BACKUP" ]]; then
        mv "$REAL_CLAUDE" "$BACKUP"
        echo "  Backed up claude -> $BACKUP"
    else
        echo "  Backup already exists at $BACKUP"
        rm -f "$REAL_CLAUDE"
    fi
elif [[ -L "$REAL_CLAUDE" ]]; then
    echo "  claude is already a symlink, removing"
    rm -f "$REAL_CLAUDE"
fi

# Install shim as 'claude' in the same directory
cp "$SHIM_SOURCE" "$LOCAL_BIN/claude"
chmod +x "$LOCAL_BIN/claude"
echo "  Installed shim at $LOCAL_BIN/claude"

# 5. Install cctx command
cp "$CCTX_SOURCE" "$LOCAL_BIN/cctx"
chmod +x "$LOCAL_BIN/cctx"
echo "  Installed cctx at $LOCAL_BIN/cctx"

echo ""
echo "=== Installation complete ==="
echo "  Real claude binary: $LOCAL_BIN/claude-real${REAL_EXT:-}"
echo "  Shim:               $LOCAL_BIN/claude"
echo "  Config manager:     $LOCAL_BIN/cctx"
echo "  Default profile:    $DEFAULT_PROFILE"
echo ""
echo "Set a profile for a project:"
echo "  cd /path/to/project"
echo "  cctx create myprofile"
echo "  jq '.profile = \"myprofile\"' .claude/settings.local.json > tmp && mv tmp .claude/settings.local.json"
