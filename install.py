#!/usr/bin/env python3
import sys
import os
import json
import shutil
import stat
import platform
import tempfile
from pathlib import Path

CLAUDE_DIR = Path.home() / '.claude'
PROFILES_DIR = CLAUDE_DIR / 'profiles'
SETTINGS_FILE = PROFILES_DIR / 'settings.json'
DEFAULT_PROFILE = PROFILES_DIR / 'default'
LOCAL_BIN = Path.home() / '.local' / 'bin'
SCRIPT_DIR = Path(__file__).parent.resolve()

IS_WINDOWS = platform.system() == 'Windows'


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def check_symlinks():
    with tempfile.NamedTemporaryFile(delete=False) as f:
        target = Path(f.name)
    link = target.parent / (target.name + '_link')
    try:
        link.symlink_to(target)
        link.unlink()
        return True
    except OSError:
        return False
    finally:
        target.unlink(missing_ok=True)


def setup_profiles():
    print("Creating profiles directory...")
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)

    if not SETTINGS_FILE.exists():
        data = {"managed_files": ["CLAUDE.md", "settings.json"]}
        SETTINGS_FILE.write_text(json.dumps(data, indent=2))
        print(f"  Created {SETTINGS_FILE}")
    else:
        print(f"  {SETTINGS_FILE} already exists, skipping")

    print("Creating default profile...")
    DEFAULT_PROFILE.mkdir(parents=True, exist_ok=True)

    managed = json.loads(SETTINGS_FILE.read_text()).get('managed_files', [])
    for f in managed:
        src = CLAUDE_DIR / f
        dst = DEFAULT_PROFILE / f

        if not src.exists() and not src.is_symlink():
            print(f"  WARN: {src} does not exist, skipping")
            continue

        if src.is_symlink() and 'profiles' in str(src.resolve()):
            print(f"  {f} already symlinked, skipping")
            continue

        if not dst.exists():
            shutil.copy2(src, dst)
            print(f"  Copied {f} -> default profile")

        src.unlink()
        src.symlink_to(dst)
        print(f"  Symlinked {src} -> {dst}")


def make_executable(path):
    path.chmod(path.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)


def install_scripts():
    print("Installing scripts...")
    LOCAL_BIN.mkdir(parents=True, exist_ok=True)

    if IS_WINDOWS:
        claude_exe = LOCAL_BIN / 'claude.exe'
        claude_real = LOCAL_BIN / 'claude-real.exe'

        if claude_exe.exists() and not claude_exe.is_symlink():
            if not claude_real.exists():
                shutil.move(str(claude_exe), claude_real)
                print(f"  Backed up claude.exe -> claude-real.exe")
            else:
                print(f"  Backup already exists at claude-real.exe")
                claude_exe.unlink()
        elif claude_real.exists():
            print(f"  claude-real.exe already present")
        else:
            die("claude.exe not found in ~/.local/bin")

        shutil.copy2(SCRIPT_DIR / 'claude-shim.py', LOCAL_BIN / 'claude-shim.py')
        shutil.copy2(SCRIPT_DIR / 'claude.cmd', LOCAL_BIN / 'claude.cmd')
        print(f"  Installed claude.cmd + claude-shim.py")

        shutil.copy2(SCRIPT_DIR / 'cctx.py', LOCAL_BIN / 'cctx.py')
        shutil.copy2(SCRIPT_DIR / 'cctx.cmd', LOCAL_BIN / 'cctx.cmd')
        print(f"  Installed cctx.cmd + cctx.py")

    else:
        claude_path = shutil.which('claude')
        if not claude_path:
            die("'claude' not found in PATH")
        real_path = Path(claude_path)

        if real_path.exists() and not real_path.is_symlink():
            backup = real_path.parent / 'claude-real'
            if not backup.exists():
                shutil.move(str(real_path), backup)
                print(f"  Backed up claude -> claude-real")
            else:
                print(f"  Backup already exists at claude-real")
                real_path.unlink()
        elif real_path.is_symlink():
            print(f"  claude is already a symlink, removing")
            real_path.unlink()

        shutil.copy2(SCRIPT_DIR / 'claude-shim.py', real_path)
        make_executable(real_path)
        print(f"  Installed shim at {real_path}")

        cctx_path = real_path.parent / 'cctx'
        shutil.copy2(SCRIPT_DIR / 'cctx.py', cctx_path)
        make_executable(cctx_path)
        print(f"  Installed cctx at {cctx_path}")


def main():
    print("=== cctx install ===")
    print(f"Platform: {'Windows' if IS_WINDOWS else platform.system()}")

    if IS_WINDOWS:
        if not check_symlinks():
            die(
                "Symlinks are not available.\n"
                "Enable Developer Mode: Settings > System > For developers > Developer Mode: ON\n"
                "Then restart your terminal."
            )
        print("Symlink support: OK")

    setup_profiles()
    install_scripts()

    print()
    print("=== Installation complete ===")
    if IS_WINDOWS:
        print(f"  Real claude binary: {LOCAL_BIN / 'claude-real.exe'}")
        print(f"  Shim (CMD):         {LOCAL_BIN / 'claude.cmd'}")
        print(f"  Config manager:     {LOCAL_BIN / 'cctx.cmd'}")
    else:
        print(f"  Real claude binary: {LOCAL_BIN / 'claude-real'}")
        print(f"  Shim:               {LOCAL_BIN / 'claude'}")
        print(f"  Config manager:     {LOCAL_BIN / 'cctx'}")
    print(f"  Default profile:    {DEFAULT_PROFILE}")
    print()
    print("Set a profile for a project:")
    print("  cd /path/to/project")
    print("  cctx create myprofile")
    print('  echo \'{"profile": "myprofile"}\' > .claude/settings.local.json')


if __name__ == '__main__':
    main()
