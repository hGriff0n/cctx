#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
SETTINGS_FILE="$PROFILES_DIR/settings.json"
DEFAULT_PROFILE="$PROFILES_DIR/default"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHIM_SOURCE="$SCRIPT_DIR/claude-shim.sh"
CCTX_SOURCE="$SCRIPT_DIR/cctx.py"
REAL_CLAUDE="$(which claude)"
LOCAL_BIN="$HOME/.local/bin"

# Detect Windows (Git Bash / MSYS)
IS_WINDOWS=false
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
esac

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

# Verify python exists (needed for cctx)
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    echo "ERROR: 'python3' is required but not found"
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

# TODO: https://github.com/hGriff0n/cctx/issues/1
# Claude seems to have validation that forces "claude.exe" to exist
# Specific error is "Install method is native but claude command not found"
# In the meantime I'm just changing the shim to `cclaude`
# Back up the real claude binary
# if [[ -f "$REAL_CLAUDE" && ! -L "$REAL_CLAUDE" ]]; then
#     REAL_EXT=""
#     [[ "$REAL_CLAUDE" == *.exe ]] && REAL_EXT=".exe"
#     BACKUP="$LOCAL_BIN/claude-real${REAL_EXT}"

#     if [[ ! -f "$BACKUP" ]]; then
#         mv "$REAL_CLAUDE" "$BACKUP"
#         echo "  Backed up claude -> $BACKUP"
#     else
#         echo "  Backup already exists at $BACKUP"
#         rm -f "$REAL_CLAUDE"
#     fi
# elif [[ -L "$REAL_CLAUDE" ]]; then
#     echo "  claude is already a symlink, removing"
#     rm -f "$REAL_CLAUDE"
# fi

if $IS_WINDOWS; then
    cp "$SCRIPT_DIR/claude.cmd" "$LOCAL_BIN/cclaude.cmd"
    echo "  Installed claude.cmd"
else
    cp "$SHIM_SOURCE" "$LOCAL_BIN/cclaude"
    chmod +x "$LOCAL_BIN/cclaude"
    echo "  Installed shim at $LOCAL_BIN/cclaude"
fi

# 5. Install cctx command
if $IS_WINDOWS; then
    cp "$CCTX_SOURCE" "$LOCAL_BIN/cctx.py"
    cp "$SCRIPT_DIR/cctx.cmd" "$LOCAL_BIN/cctx.cmd"
    echo "  Installed cctx.cmd + cctx.py"
else
    cp "$CCTX_SOURCE" "$LOCAL_BIN/cctx"
    chmod +x "$LOCAL_BIN/cctx"
    echo "  Installed cctx at $LOCAL_BIN/cctx"
fi

echo ""
echo "=== Installation complete ==="
echo "  Real claude binary: $LOCAL_BIN/claude-real${REAL_EXT:-}"
if $IS_WINDOWS; then
    echo "  Shim (CMD):         $LOCAL_BIN/claude.cmd"
    echo "  Config manager:     $LOCAL_BIN/cctx.cmd"
else
    echo "  Shim:               $LOCAL_BIN/claude"
    echo "  Config manager:     $LOCAL_BIN/cctx"
fi
echo "  Default profile:    $DEFAULT_PROFILE"
echo ""
echo "Set a profile for a project:"
echo "  cd /path/to/project"
echo "  cctx create myprofile"
echo "  jq '.profile = \"myprofile\"' .claude/settings.local.json > tmp && mv tmp .claude/settings.local.json"
