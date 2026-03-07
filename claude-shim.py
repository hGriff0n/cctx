#!/usr/bin/env python3
import sys
import os
import json
import subprocess
from pathlib import Path

CLAUDE_DIR = Path.home() / '.claude'
PROFILES_DIR = CLAUDE_DIR / 'profiles'
SETTINGS_FILE = PROFILES_DIR / 'settings.json'


def find_real_claude():
    local_bin = Path.home() / '.local' / 'bin'
    for name in ('claude-real', 'claude-real.exe'):
        p = local_bin / name
        if p.exists():
            return p
    return None


def get_profile():
    local_settings = Path.cwd() / '.claude' / 'settings.local.json'
    if local_settings.exists():
        try:
            data = json.loads(local_settings.read_text())
            p = data.get('profile', '').strip()
            if p:
                return p
        except (json.JSONDecodeError, OSError):
            pass
    return 'default'


def load_profile(profile):
    profile_dir = PROFILES_DIR / profile
    if not profile_dir.is_dir():
        available = sorted(p.name for p in PROFILES_DIR.iterdir() if p.is_dir())
        print(f"ERROR: Profile '{profile}' not found. Available: {', '.join(available)}", file=sys.stderr)
        sys.exit(1)

    if not SETTINGS_FILE.exists():
        return

    managed = json.loads(SETTINGS_FILE.read_text()).get('managed_files', [])
    for f in managed:
        link = CLAUDE_DIR / f
        target = profile_dir / f
        if target.exists() or target.is_symlink():
            if link.exists() or link.is_symlink():
                link.unlink()
            link.symlink_to(target)


def main():
    real = find_real_claude()
    if not real:
        print("ERROR: Real claude binary not found at ~/.local/bin/claude-real[.exe]", file=sys.stderr)
        sys.exit(1)

    load_profile(get_profile())

    result = subprocess.run([str(real)] + sys.argv[1:])
    sys.exit(result.returncode)


main()
