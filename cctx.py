#!/usr/bin/env python3
import sys
import os
import json
import shutil
import argparse
from pathlib import Path

CLAUDE_DIR = Path.home() / '.claude'
PROFILES_DIR = CLAUDE_DIR / 'profiles'
SETTINGS_FILE = PROFILES_DIR / 'settings.json'
ALWAYS_COPY = {'CLAUDE.md', 'settings.json'}


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def ensure_profiles():
    if not PROFILES_DIR.is_dir():
        die("Profiles directory not found. Run install.py first.")
    if not SETTINGS_FILE.exists():
        die(f"Settings file not found at {SETTINGS_FILE}")


def read_settings():
    return json.loads(SETTINGS_FILE.read_text())


def write_settings(data):
    SETTINGS_FILE.write_text(json.dumps(data, indent=2))


def get_managed_files():
    return read_settings().get('managed_files', [])


def profile_exists(name):
    return (PROFILES_DIR / name).is_dir()


# --- Commands ---

def cmd_create(args):
    if not profile_exists(args.base):
        die(f"Base profile '{args.base}' not found")
    if profile_exists(args.profile):
        die(f"Profile '{args.profile}' already exists")

    print(f"Creating profile '{args.profile}' from base '{args.base}'...")
    profile_dir = PROFILES_DIR / args.profile
    profile_dir.mkdir(parents=True)

    base_dir = PROFILES_DIR / args.base
    for f in get_managed_files():
        src = base_dir / f
        dst = profile_dir / f
        dst.parent.mkdir(parents=True, exist_ok=True)

        if f in ALWAYS_COPY:
            if src.exists():
                shutil.copy2(src, dst)
                print(f"  Copied {f}")
            continue

        if args.use_symlink:
            if src.is_symlink():
                dst.symlink_to(src.resolve())
                print(f"  Symlinked {f} -> {src.resolve()} (copied link from base)")
            elif src.exists():
                dst.symlink_to(src.resolve())
                print(f"  Symlinked {f} -> {src}")
        else:
            if src.exists():
                shutil.copy2(src, dst)
                print(f"  Copied {f}")

    print(f"Profile '{args.profile}' created.")


def cmd_managed(args):
    if args.add:
        path = args.add
        full = CLAUDE_DIR / path
        if not full.exists():
            die(f"{full} does not exist")
        if full.is_symlink():
            die(f"{full} is already a symlink (already managed?)")

        settings = read_settings()
        if path in settings.get('managed_files', []):
            die(f"'{path}' is already in managed_files")

        default_dst = PROFILES_DIR / 'default' / path
        default_dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(full), default_dst)
        full.symlink_to(default_dst)
        print(f"Moved {path} to default profile and created symlink")

        for profile_dir in sorted(PROFILES_DIR.iterdir()):
            if not profile_dir.is_dir() or profile_dir.name == 'default':
                continue
            pdst = profile_dir / path
            if not pdst.exists() and not pdst.is_symlink():
                pdst.parent.mkdir(parents=True, exist_ok=True)
                pdst.symlink_to(default_dst)
                print(f"  Created symlink in profile '{profile_dir.name}'")

        settings.setdefault('managed_files', []).append(path)
        write_settings(settings)
        print(f"Added '{path}' to managed_files")

    elif args.remove:
        path = args.remove
        if path in ALWAYS_COPY:
            die(f"Cannot remove '{path}' from managed files")
        settings = read_settings()
        managed = settings.get('managed_files', [])
        if path not in managed:
            die(f"'{path}' is not in managed_files")
        managed.remove(path)
        write_settings(settings)
        print(f"Removed '{path}' from managed_files")

    else:
        print("Managed files:")
        for f in get_managed_files():
            print(f"  {f}")


def cmd_unlink(args):
    if not profile_exists(args.profile):
        die(f"Profile '{args.profile}' not found")

    target = PROFILES_DIR / args.profile / args.file
    if not target.is_symlink():
        if target.exists():
            print(f"'{args.file}' in profile '{args.profile}' is already a regular file")
        else:
            die(f"'{args.file}' does not exist in profile '{args.profile}'")
        return

    real_file = target.resolve()
    if not real_file.is_file():
        die(f"Symlink target '{real_file}' does not exist")

    target.unlink()
    shutil.copy2(real_file, target)
    print(f"Unlinked '{args.file}' in profile '{args.profile}' (copied from {real_file})")


def cmd_list(args):
    print("Profiles:")
    for p in sorted(p.name for p in PROFILES_DIR.iterdir() if p.is_dir()):
        print(f"  {p}")


def cmd_current(args):
    profile = 'default'
    local_settings = Path.cwd() / '.claude' / 'settings.local.json'
    if local_settings.exists():
        try:
            data = json.loads(local_settings.read_text())
            p = data.get('profile', '').strip()
            if p:
                profile = p
        except (json.JSONDecodeError, OSError):
            pass
    print(profile)


# --- Main ---

def main():
    ensure_profiles()

    parser = argparse.ArgumentParser(prog='cctx', description='Claude Code context/profile manager')
    sub = parser.add_subparsers(dest='command')
    sub.required = True

    p_create = sub.add_parser('create', help='Create a new profile')
    p_create.add_argument('profile', help='Profile name')
    p_create.add_argument('--base', default='default', metavar='PROFILE',
                          help='Base profile to copy from (default: "default")')
    p_create.add_argument('--use_symlink', action='store_true',
                          help='Symlink files from base instead of copying (CLAUDE.md and settings.json are always copied)')
    p_create.set_defaults(func=cmd_create)

    p_managed = sub.add_parser('managed', help='Manage tracked files across profiles')
    p_managed.add_argument('--add', metavar='PATH', help='Add a file to managed list')
    p_managed.add_argument('--remove', metavar='PATH', help='Remove a file from managed list')
    p_managed.set_defaults(func=cmd_managed)

    p_unlink = sub.add_parser('unlink', help='Replace a symlinked file in a profile with a real copy')
    p_unlink.add_argument('profile', help='Profile name')
    p_unlink.add_argument('file', help='File name')
    p_unlink.set_defaults(func=cmd_unlink)

    p_list = sub.add_parser('list', help='List all profiles')
    p_list.set_defaults(func=cmd_list)

    p_current = sub.add_parser('current', help='Show which profile the current directory would use')
    p_current.set_defaults(func=cmd_current)

    args = parser.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
