#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
SETTINGS_FILE="$PROFILES_DIR/settings.json"

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

ensure_profiles() {
    [[ -d "$PROFILES_DIR" ]] || die "Profiles directory not found. Run install.sh first."
    [[ -f "$SETTINGS_FILE" ]] || die "Settings file not found at $SETTINGS_FILE"
}

get_managed_files() {
    jq -r '.managed_files[]' "$SETTINGS_FILE"
}

list_profiles() {
    ls -1 "$PROFILES_DIR" | grep -v '^settings\.json$'
}

profile_exists() {
    [[ -d "$PROFILES_DIR/$1" ]]
}

# --- Commands ---

cmd_create() {
    local profile=""
    local base="default"
    local use_symlink=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base) base="$2"; shift 2 ;;
            --use_symlink) use_symlink=true; shift ;;
            -*) die "Unknown flag: $1" ;;
            *) profile="$1"; shift ;;
        esac
    done

    [[ -n "$profile" ]] || die "Usage: cctx create <profile> [--base <profile>] [--use_symlink]"
    profile_exists "$base" || die "Base profile '$base' not found"
    [[ -d "$PROFILES_DIR/$profile" ]] && die "Profile '$profile' already exists"

    echo "Creating profile '$profile' from base '$base'..."
    mkdir -p "$PROFILES_DIR/$profile"

    local base_dir="$PROFILES_DIR/$base"
    local managed_files
    managed_files=$(get_managed_files)

    while IFS= read -r file; do
        local src="$base_dir/$file"
        local dst="$PROFILES_DIR/$profile/$file"

        # CLAUDE.md and settings.json are ALWAYS copied, never symlinked
        if [[ "$file" == "CLAUDE.md" || "$file" == "settings.json" ]]; then
            if [[ -e "$src" ]]; then
                cp "$src" "$dst"
                echo "  Copied $file"
            fi
            continue
        fi

        if $use_symlink; then
            if [[ -L "$src" ]]; then
                # If base file is itself a symlink, copy the link target
                link_target=$(readlink "$src")
                ln -s "$link_target" "$dst"
                echo "  Symlinked $file -> $link_target (copied link from base)"
            elif [[ -e "$src" ]]; then
                ln -s "$src" "$dst"
                echo "  Symlinked $file -> $src"
            fi
        else
            if [[ -e "$src" ]]; then
                cp "$src" "$dst"
                echo "  Copied $file"
            fi
        fi
    done <<< "$managed_files"

    echo "Profile '$profile' created."
}

cmd_managed() {
    local add_path=""
    local remove_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --add) add_path="$2"; shift 2 ;;
            --remove) remove_path="$2"; shift 2 ;;
            -*) die "Unknown flag: $1" ;;
            *) die "Unknown argument: $1" ;;
        esac
    done

    if [[ -n "$add_path" ]]; then
        # Add a file to managed list
        local full_path="$CLAUDE_DIR/$add_path"
        [[ -e "$full_path" ]] || die "$full_path does not exist"
        [[ -L "$full_path" ]] && die "$full_path is already a symlink (already managed?)"

        # Check if already managed
        if jq -e --arg f "$add_path" '.managed_files | index($f)' "$SETTINGS_FILE" &>/dev/null; then
            die "'$add_path' is already in managed_files"
        fi

        # Move to default profile
        local default_dst="$PROFILES_DIR/default/$add_path"
        mkdir -p "$(dirname "$default_dst")"
        mv "$full_path" "$default_dst"
        ln -s "$default_dst" "$full_path"
        echo "Moved $add_path to default profile and created symlink"

        # Create symlinks in all other profiles
        for profile_dir in "$PROFILES_DIR"/*/; do
            local pname
            pname=$(basename "$profile_dir")
            [[ "$pname" == "default" ]] && continue
            local pdst="$profile_dir$add_path"
            if [[ ! -e "$pdst" && ! -L "$pdst" ]]; then
                mkdir -p "$(dirname "$pdst")"
                ln -s "$default_dst" "$pdst"
                echo "  Created symlink in profile '$pname'"
            fi
        done

        # Update settings.json
        jq --arg f "$add_path" '.managed_files += [$f]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "Added '$add_path' to managed_files"

    elif [[ -n "$remove_path" ]]; then
        # Remove a file from managed list
        if [[ "$remove_path" == "CLAUDE.md" || "$remove_path" == "settings.json" ]]; then
            die "Cannot remove '$remove_path' from managed files"
        fi

        if ! jq -e --arg f "$remove_path" '.managed_files | index($f)' "$SETTINGS_FILE" &>/dev/null; then
            die "'$remove_path' is not in managed_files"
        fi

        jq --arg f "$remove_path" '.managed_files -= [$f]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "Removed '$remove_path' from managed_files"

    else
        # List managed files
        echo "Managed files:"
        get_managed_files | while IFS= read -r f; do
            echo "  $f"
        done
    fi
}

cmd_unlink() {
    local profile="${1:-}"
    local file="${2:-}"

    [[ -n "$profile" && -n "$file" ]] || die "Usage: cctx unlink <profile> <file>"
    profile_exists "$profile" || die "Profile '$profile' not found"

    local target="$PROFILES_DIR/$profile/$file"
    if [[ ! -L "$target" ]]; then
        if [[ -e "$target" ]]; then
            echo "'$file' in profile '$profile' is already a regular file"
        else
            die "'$file' does not exist in profile '$profile'"
        fi
        return
    fi

    # Resolve the symlink and copy the actual file
    local real_file
    real_file=$(readlink -f "$target")
    [[ -f "$real_file" ]] || die "Symlink target '$real_file' does not exist"

    rm "$target"
    cp "$real_file" "$target"
    echo "Unlinked '$file' in profile '$profile' (copied from $real_file)"
}

cmd_list() {
    echo "Profiles:"
    list_profiles | while IFS= read -r p; do
        echo "  $p"
    done
}

cmd_current() {
    local profile="default"
    local local_settings="$(pwd)/.claude/settings.local.json"
    if [[ -f "$local_settings" ]]; then
        local p
        p=$(jq -r '.profile // empty' "$local_settings" 2>/dev/null || true)
        [[ -n "$p" ]] && profile="$p"
    fi
    echo "$profile"
}

cmd_help() {
    cat <<'HELP'
cctx - Claude Code context/profile manager

Usage:
  cctx create <profile> [--base <profile>] [--use_symlink]
      Create a new profile, optionally based on another profile.
      --base <profile>   Base profile to copy from (default: "default")
      --use_symlink      Symlink files from base instead of copying
                         (CLAUDE.md and settings.json are always copied)

  cctx managed [--add <path>] [--remove <path>]
      Manage the list of files tracked across profiles.
      No flags: list managed files.
      --add <path>       Add a file to managed list (moves to default profile)
      --remove <path>    Remove a file from managed list

  cctx unlink <profile> <file>
      Replace a symlinked file in a profile with a real copy.

  cctx list
      List all available profiles.

  cctx current
      Show which profile the current directory would use.
HELP
}

# --- Main ---

ensure_profiles

case "${1:-help}" in
    create)  shift; cmd_create "$@" ;;
    managed) shift; cmd_managed "$@" ;;
    unlink)  shift; cmd_unlink "$@" ;;
    list)    cmd_list ;;
    current) cmd_current ;;
    help|--help|-h) cmd_help ;;
    *) die "Unknown command: $1. Run 'cctx help' for usage." ;;
esac
