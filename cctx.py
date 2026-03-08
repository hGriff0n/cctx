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

# TODO: Definitely need to log/reroute output
# TODO: Create empty CLAUDE if doesn't exist
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

        # Collect profiles with a real (non-symlinked) copy of the file
        real_copies = {}
        for profile_dir in sorted(PROFILES_DIR.iterdir()):
            if not profile_dir.is_dir():
                continue
            f = profile_dir / path
            if f.exists() and not f.is_symlink():
                real_copies[profile_dir.name] = f

        if not real_copies:
            die(f"No real copy of '{path}' found in any profile; cannot revert")

        if len(real_copies) == 1:
            src_profile, src_file = next(iter(real_copies.items()))
        else:
            # Check if all real copies are identical
            contents = {name: f.read_bytes() for name, f in real_copies.items()}
            unique = set(contents.values())
            if len(unique) == 1:
                src_profile, src_file = next(iter(real_copies.items()))
            else:
                print(f"WARNING: Multiple profiles have different real copies of '{path}':")
                for name in sorted(real_copies):
                    print(f"  {name}")
                print("Restoring will discard all but one version.")
                answer = input("Continue? [y/N] ").strip().lower()
                if answer != 'y':
                    print("Aborted.")
                    return
                chosen = input(f"Which profile's version to restore? [{'/'.join(sorted(real_copies))}] ").strip()
                if chosen not in real_copies:
                    die(f"Unknown profile '{chosen}'")
                src_profile, src_file = chosen, real_copies[chosen]

        live_link = CLAUDE_DIR / path
        if live_link.is_symlink() or live_link.exists():
            live_link.unlink()
        shutil.move(str(src_file), live_link)
        print(f"Restored {path} from profile '{src_profile}' to {live_link}")

        managed.remove(path)
        write_settings(settings)
        print(f"Removed '{path}' from managed_files")

        for profile_dir in sorted(PROFILES_DIR.iterdir()):
            if not profile_dir.is_dir():
                continue
            f = profile_dir / path
            if f.is_symlink() or f.exists():
                f.unlink()

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


def cmd_link(args):
    if not profile_exists(args.profile):
        die(f"Profile '{args.profile}' not found")
    if not profile_exists(args.target):
        die(f"Target profile '{args.target}' not found")

    link_target = PROFILES_DIR / args.target / args.file
    if not link_target.exists():
        die(f"'{args.file}' does not exist in target profile '{args.target}'")

    src = PROFILES_DIR / args.profile / args.file
    if src.is_symlink() and src.resolve() == link_target.resolve():
        print(f"'{args.file}' in profile '{args.profile}' is already linked to '{args.target}'")
        return

    if src.exists() or src.is_symlink():
        src.unlink()

    src.symlink_to(link_target.resolve())
    print(f"Linked '{args.file}' in profile '{args.profile}' -> {link_target.resolve()}")


def cmd_set(args):
    if not profile_exists(args.profile):
        die(f"Profile '{args.profile}' not found")

    profile_dir = PROFILES_DIR / args.profile
    for f in get_managed_files():
        link = CLAUDE_DIR / f
        target = profile_dir / f
        if target.exists() or target.is_symlink():
            if link.exists() or link.is_symlink():
                link.unlink()
            link.symlink_to(target)

    print(f"Switched to profile '{args.profile}'")


def cmd_list(args):
    if args.managed:
        print("Managed files:")
        for f in get_managed_files():
            print(f"  {f}")
    else:
        print("Profiles:")
        for p in sorted(p.name for p in PROFILES_DIR.iterdir() if p.is_dir()):
            print(f"  {p}")


def current_profile():
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


def cmd_resolve(args):
    profiles = [p for p in PROFILES_DIR.iterdir() if p.is_dir()]

    # Pass 1: collect union of all enabledPlugins keys from non-symlinked settings
    union = {}
    for profile_dir in profiles:
        s = profile_dir / 'settings.json'
        if s.is_symlink() or not s.exists():
            continue
        data = json.loads(s.read_text())
        for key in data.get('enabledPlugins', {}):
            union[key] = union.get(key, False)

    if not union:
        print("No enabledPlugins found across any profile.")
        return

    print(f"Plugin union ({len(union)}): {', '.join(sorted(union))}")

    # Pass 2: update each non-symlinked settings.json with any missing plugins
    for profile_dir in sorted(profiles, key=lambda p: p.name):
        s = profile_dir / 'settings.json'
        if s.is_symlink() or not s.exists():
            print(f"  {profile_dir.name}: skipped (symlink or missing)")
            continue
        data = json.loads(s.read_text())
        enabled = data.setdefault('enabledPlugins', {})
        added = [k for k in union if k not in enabled]
        for k in added:
            enabled[k] = False
        if added:
            s.write_text(json.dumps(data, indent=2))
            print(f"  {profile_dir.name}: added {added}")
        else:
            print(f"  {profile_dir.name}: up to date")


# --- Main ---

def main():
    ensure_profiles()

    parser = argparse.ArgumentParser(prog='cctx', description='Claude Code context/profile manager')
    sub = parser.add_subparsers(dest='command')

    p_create = sub.add_parser('create', help='Create a new profile')
    p_create.add_argument('profile', help='Profile name')
    p_create.add_argument('--base', default='default', metavar='PROFILE',
                          help='Base profile to copy from (default: "default")')
    p_create.add_argument('--use_symlink', action='store_true',
                          help='Symlink files from base instead of copying (CLAUDE.md and settings.json are always copied)')
    p_create.set_defaults(func=cmd_create)

    p_set = sub.add_parser('set', help='Activate a profile by updating symlinks in ~/.claude/')
    p_set.add_argument('profile', help='Profile name')
    p_set.set_defaults(func=cmd_set)

    p_managed = sub.add_parser('managed', help='Manage tracked files across profiles')
    p_managed.add_argument('--add', metavar='PATH', help='Add a file to managed list')
    p_managed.add_argument('--remove', metavar='PATH', help='Remove a file from managed list')
    p_managed.set_defaults(func=cmd_managed)

    # TODO: This could be moved to a subcommand of `set`
    # `cctx set <profile> --unlink <file>`
    # Or maybe `cctx <profile> unlink <file>`
    p_unlink = sub.add_parser('unlink', help='Replace a symlinked file in a profile with a real copy')
    p_unlink.add_argument('profile', help='Profile name')
    p_unlink.add_argument('file', help='File name')
    p_unlink.set_defaults(func=cmd_unlink)

    p_link = sub.add_parser('link', help='Replace a file in a profile with a symlink to another profile\'s copy')
    p_link.add_argument('profile', help='Profile name')
    p_link.add_argument('file', help='File name')
    p_link.add_argument('target', metavar='TARGET_PROFILE', help='Profile to symlink from')
    p_link.set_defaults(func=cmd_link)

    p_list = sub.add_parser('list', help='List all profiles (or managed files with --managed)')
    p_list.add_argument('--managed', action='store_true', help='List managed files instead of profiles')
    p_list.set_defaults(func=cmd_list)

    p_resolve = sub.add_parser('resolve', help='Sync enabledPlugins across all non-symlinked profiles')
    p_resolve.set_defaults(func=cmd_resolve)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        print()
        print(f"Current Active Profile: {current_profile()}")
        return
    args.func(args)


if __name__ == '__main__':
    main()
