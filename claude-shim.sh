#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
SETTINGS_FILE="$PROFILES_DIR/settings.json"
REAL_CLAUDE="$HOME/.local/bin/claude-real"

# Fallback: check for .exe variant on Windows
if [[ ! -f "$REAL_CLAUDE" && -f "${REAL_CLAUDE}.exe" ]]; then
    REAL_CLAUDE="${REAL_CLAUDE}.exe"
fi

if [[ ! -f "$REAL_CLAUDE" ]]; then
    echo "ERROR: Real claude binary not found at $REAL_CLAUDE" >&2
    exit 1
fi

# Determine which profile to load
profile="default"
local_settings="$(pwd)/.claude/settings.local.json"
if [[ -f "$local_settings" ]] && command -v jq &>/dev/null; then
    p=$(jq -r '.profile // empty' "$local_settings" 2>/dev/null || true)
    if [[ -n "$p" ]]; then
        profile="$p"
    fi
fi

profile_dir="$PROFILES_DIR/$profile"
if [[ ! -d "$profile_dir" ]]; then
    echo "ERROR: Profile '$profile' not found at $profile_dir" >&2
    echo "Available profiles:" >&2
    ls -1 "$PROFILES_DIR" | grep -v '^settings\.json$' >&2
    exit 1
fi

# Load profile by updating symlinks
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
    managed_files=$(jq -r '.managed_files[]' "$SETTINGS_FILE")
    while IFS= read -r file; do
        link="$CLAUDE_DIR/$file"
        target="$profile_dir/$file"

        # Only update if target exists in the profile
        if [[ -e "$target" || -L "$target" ]]; then
            rm -f "$link"
            ln -s "$target" "$link"
        fi
    done <<< "$managed_files"
fi

# Transfer to real claude
exec "$REAL_CLAUDE" "$@"
