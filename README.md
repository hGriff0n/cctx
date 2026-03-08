# cctx

Profile support for [Claude Code](https://claude.ai/claude-code). Switch between different `CLAUDE.md` and `settings.json` configurations automatically based on your working directory.

## How it works

cctx manages a `~/.claude/profiles/` directory. Each profile is a folder of config files. The `cclaude` shim checks for a `"profile"` field in the current project's `.claude/settings.local.json` and swaps the symlinks in `~/.claude/` to point to that profile before handing off to the real `claude` binary.

```
~/.claude/
  CLAUDE.md            -> symlink to profiles/myprofile/CLAUDE.md
  settings.json        -> symlink to profiles/myprofile/settings.json
  profiles/
    settings.json      # list of managed files
    default/
      CLAUDE.md
      settings.json
    myprofile/
      CLAUDE.md
      settings.json
```

## Requirements

- Python 3.8+
- **Windows**: [Developer Mode enabled](ms-settings:developers) (required for symlinks)

## Install

```bash
# Clone or copy this repo, then:
install.sh             # macOS/Linux
install.cmd            # Windows (from CMD/PowerShell)
```

The installer:
1. Creates `~/.claude/profiles/` and a `default` profile from your current `~/.claude` files
2. Installs the shim as `cclaude` and the config manager as `cctx`

## Usage

### Set a profile for a project

Create a profile and assign it to a project:

```bash
cctx create work
cd /path/to/project
mkdir -p .claude
echo '{"profile": "work"}' > .claude/settings.local.json
```

Now `claude` in that directory will automatically load the `work` profile.

### cctx commands

```
cctx
    Prints help and shows the active profile for the current directory

cctx list
    List all available profiles.

cctx create <profile> [--base <profile>] [--use_symlink]
    Create a new profile copied from a base profile (default: "default").
    --base <profile>   Profile to copy from
    --use_symlink      Symlink files from base instead of copying.
                       CLAUDE.md and settings.json are always copied.

cctx managed
    List files tracked across all profiles.

cctx managed --add <path>
    Start tracking a file. Path is relative to ~/.claude/.
    The file is moved to the default profile; symlinks are created
    in all other profiles.

cctx managed --remove <path>
    Stop tracking a file (cannot remove CLAUDE.md or settings.json).

cctx link <profile> <file> <target>
    Replace a local file in a profile with a symlink to the same file in a different profile.

cctx unlink <profile> <file>
    Replace a symlinked file in a profile with a real independent copy.
```

## Managed files

By default, cctx tracks `CLAUDE.md` and `settings.json`. You can track additional files:

```bash
cctx managed --add commands/my-command.md
cctx managed
# CLAUDE.md
# settings.json
# commands/my-command.md
```

## Profiles with shared files

Use `--use_symlink` when creating a profile to share files from the base profile rather than copy them. Edits to the shared file affect all profiles that link to it. `CLAUDE.md` and `settings.json` are always given independent copies.

You can additionally link specific files with:

```bash
cctx link myprofile some-shared-file.md target
```

To later make a symlinked file independent:

```bash
cctx unlink myprofile some-shared-file.md
```

## Windows notes

The `.cmd` wrappers (`install.cmd`, `cctx.cmd`, `claude.cmd`) call the corresponding `.py` scripts via Python. Once installed, `cctx` and `claude` work from CMD, PowerShell, and Git Bash.

Symlinks on Windows require Developer Mode. The installer checks for this and exits early with instructions if symlinks aren't available.
