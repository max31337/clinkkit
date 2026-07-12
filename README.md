<p align="center">
  <a href="https://github.com/max31337/ClinkKit">
    <img src="clinkkit-banner.svg" width="700" alt="ClinkKit">
  </a>
</p>

**Modern productivity toolkit for Clink**  
*Currently featuring HistoryGuard: intelligent command-history protection for Windows CMD.*

## Overview

ClinkKit is a modular Lua toolkit for [Clink](https://chrisant996.github.io/clink/) on Windows CMD. Its first implemented feature is **HistoryGuard**, which keeps typos, accidental input, and unwanted commands out of persistent Clink history.

<p align="center">
  🌐 <a href="https://clinkkit.pages.dev/">Documentation & Website</a>
</p>

```text
C:\repo> git stauts
HistoryGuard: didn't save to history. Did you mean:  git status
git: 'stauts' is not a git command. See 'git --help'.
```

HistoryGuard does not block or rewrite command execution. CMD and the invoked program still handle the command normally; HistoryGuard only decides whether Clink saves it in history.

## Features available now

### HistoryGuard

- Excludes commands in a configurable blacklist from history.
- Detects punctuation-only input and conservative keyboard-smash patterns.
- Detects unknown executables, with a nearby executable suggestion when available.
- Detects first-subcommand typos, such as `git stauts`.
- Detects long-option typos, such as `rg --hlep`.
- Offers optional strict subcommand filtering for unrelated input such as `git asdfgh`.
- Cleans existing persisted history, with backups, duplicate removal, dry runs, and an optional `Alt-Ctrl-H` shortcut.
- Fails open: an internal HistoryGuard error keeps the history entry rather than disrupting your shell.

Today, exclusion is name-based: `hg.blacklist` matches whole command names (e.g. `history`, `cls`). HistoryGuard does not yet inspect the full argument text of a line, so it cannot currently tell that a command *contains* something sensitive — see **Sensitive-data protection (planned)** below.

### Decision order

For each accepted input line, HistoryGuard checks:

1. Blank input is kept.
2. Blacklisted commands are excluded silently.
3. Punctuation-only input and keyboard-smash patterns are excluded.
4. Unknown executables are excluded when enabled.
5. First-subcommand typos and strict subcommand checks are applied when enabled.
6. Long-option typos are checked when enabled.
7. All remaining lines are kept.

## Requirements

- Windows CMD with Clink injected.
- Clink 1.5.13 or later for the history callback; Clink 1.9.27 or later is recommended.

From a Clink-enabled CMD prompt:

```cmd
clink --version
```

## Installation

Copy both the loader and module directory into your Clink profile. The usual profile is `%LOCALAPPDATA%\clink`; use `clink info` to confirm yours.

```text
%LOCALAPPDATA%\clink\00_clinkkit.lua
%LOCALAPPDATA%\clink\clinkkit\
```

`00_clinkkit.lua` loads the modules in `clinkkit`, so both are required. Start a new CMD session or press `Ctrl-X`, then `Ctrl-R` to load an updated installation.

Confirm that HistoryGuard registered its settings:

```cmd
clink set hg.max_distance
```

No separate Lua installation is needed to use ClinkKit; Clink provides the runtime.

## Configuration

All options are normal Clink settings:

```cmd
clink set hg.max_distance 2
```

Once this version of ClinkKit is loaded, a command of the form `clink set hg.* ...` refreshes HistoryGuard configuration at the next prompt. It reloads settings only, not all Lua scripts, so ordinary setting changes do not require restarting CMD. Reload scripts once after changing ClinkKit files or upgrading.

| Setting | Default | Description |
|---|---:|---|
| `hg.typo_detect` | `true` | Master switch for subcommand and long-option typo checks. |
| `hg.key_smash` | `true` | Exclude punctuation-only input and conservative keyboard-smash patterns. |
| `hg.unknown_exe` | `true` | Exclude unrecognized executable names. Paths, CMD builtins, doskey aliases, and whitelisted names are allowed. |
| `hg.subcmd_detect` | `true` | Check the first non-option word after a command as a subcommand. |
| `hg.strict_subcommands` | `false` | Exclude an unknown discovered subcommand even without a close suggestion. May reject aliases, plugins, or extensions. |
| `hg.option_detect` | `true` | Check `--long-option` spelling. |
| `hg.max_distance` | `2` | Maximum Levenshtein distance for a typo suggestion. A letter transposition counts as two edits. |
| `hg.whitelist` | `git,go,cargo,python,py,node,npm,pnpm,yarn,dotnet,code,nvim,vim,rg,fd,docker,kubectl,gh,clink` | Comma-separated executable names treated as known. |
| `hg.blacklist` | `cls,history,exit,clear` | Comma-separated command names never saved to history. |
| `hg.show_suggestions` | `true` | Print an explanation or suggestion when a non-blacklisted line is excluded. |
| `hg.verbose_logging` | `WARN` | Logging level: `OFF`, `WARN`, `INFO`, or `DEBUG`. Messages go to Clink's log. |
| `hg.enable_cleanup` | `true` | Allow history cleanup. |
| `hg.cleanup_on_start` | `false` | Run one cleanup pass after the first displayed prompt. |
| `hg.cache_days` | `7` | Days before command help caches are refreshed. |
| `hg.cleanup_unknown_exe` | `false` | Enable executable checks during cleanup. Slower because it can invoke `where`. |
| `hg.cleanup_option_detect` | `false` | Enable option checks during cleanup. Slower because it can build command-help caches. |
| `hg.enable_cleanup_keybinding` | `false` | Enable `Alt-Ctrl-H` cleanup. Reload scripts after enabling it. |

### Strict subcommands

Strict mode is useful when you want `git asdfgh` excluded from history even though it is not close enough to suggest `git add` or another real command:

```cmd
clink set hg.strict_subcommands true
clink set hg.max_distance 2
```

Strict mode only acts when ClinkKit has discovered a non-empty subcommand list from the tool's help output. It can exclude legitimate Git aliases, external subcommands, and plugin commands; disable it if you rely on those.

## Cleanup existing history

HistoryGuard can scan the active persisted `clink_history`, remove entries rejected by the current cleanup rules, remove exact duplicates, and preserve valid entry order.

Every non-dry cleanup creates a timestamped backup first:

```text
%LOCALAPPDATA%\clink\historyguard_backups\
```

Enable the optional hotkey:

```cmd
clink set hg.enable_cleanup_keybinding true
```

Reload scripts once, then press `Alt-Ctrl-H` at a Clink prompt. The binding invokes `historyguard_run_cleanup` and is also added to `.inputrc` when enabled.

For a dry run from a Lua debugging context:

```lua
require("history_cleanup").run({ dry_run = true })
```

Dry runs report what would change but do not write the history file or create a backup.

### Cleanup speed

Cleanup scans the persisted history each time it runs. The first run is expected to be slower when any of these are enabled:

```cmd
clink set hg.cleanup_unknown_exe true
clink set hg.cleanup_option_detect true
clink set hg.max_distance 10
```

Command-help discovery is cached on disk under `%LOCALAPPDATA%\clink\historyguard_cache\`. Unchanged entries are also cached in memory for repeated cleanup runs in the same CMD session.

## Limitations

- HistoryGuard checks the executable, first subcommand, and long options. It does not validate ordinary arguments, paths, or nested subcommands.
- Help output is free-form text, so subcommand and option discovery is deliberately conservative. Some tools may have no discovered entries.
- Keyboard-smash detection is intentionally conservative. Unknown-executable detection is the broader protection for names such as `asdf`.
- A large `hg.max_distance` makes more distant suggestions possible but costs more comparison work. Prefer strict mode for rejecting unrelated subcommands.
- Cleanup writes Clink's documented history format directly. Keep the automatic backups and re-test after a major Clink upgrade.
- HistoryGuard does not currently scan argument content for secrets. A command that embeds a password, API key, or token is saved to history as long as the command name itself is not blacklisted — see the planned sensitive-data protection below.

## Project roadmap

ClinkKit is intentionally broader than HistoryGuard. HistoryGuard is the first module and current entry point; it will eventually become one independently loadable feature among several.

### HistoryGuard enhancements (planned)

- **Sensitive-data protection** — detect likely passwords, API keys, access tokens, connection strings, and other secrets appearing anywhere in a command line (not just the command name) and exclude the line from history, even when the command itself is not blacklisted.
- Configurable, pattern/regex-based secret detectors with a way to add custom patterns for project- or vendor-specific token formats.
- An allowlist/denylist for known false positives (e.g. long hashes or IDs that aren't secrets).
- Optional redaction mode: keep a redacted version of the command in history (with the secret portion masked) instead of dropping the entry entirely.
- Applies to both the live per-command check and the `history_cleanup` pass, so existing history can be scrubbed of secrets already saved before this feature existed.

### Planned modules

- **Aliases**
  - User-defined aliases
  - Import and export
  - Alias management commands
- **Utilities**
  - Safe `trash` command
  - `mkcd`
  - File and directory helpers
  - Additional productivity commands

The long-term design is a lightweight bootstrapper plus independently loadable feature modules sharing configuration, logging, caching, and utilities.

```text
clinkkit/
  bootstrap.lua                 Future loader
  historyguard/                 Current feature, planned module layout
  aliases/                      Planned
  utilities/                    Planned
  shared/                       Planned shared helpers
```

## Project structure today

```text
00_clinkkit.lua          Profile loader
clinkkit/
  history_guard.lua      Clink event handlers and startup
  history_evaluator.lua  Shared history decision pipeline
  history_cleanup.lua    Persisted-history cleanup
  command_cache.lua      Help-output discovery and disk cache
  executable.lua         Executable lookup and suggestions
  config.lua             Clink settings
  keybindings.lua        Optional cleanup hotkey
  tests/                 Automated and manual verification
```

## Testing

Run the automated suite from the `clinkkit\tests` directory:

```cmd
lua run_tests.lua
```

The suite uses a standard Lua interpreter with mocked Clink APIs. The passing-assertion count can grow over time; success means it ends with `0 failed`.

For end-to-end checks in a real Clink session, see [tests/manual_tests.md](tests/manual_tests.md).

## License

MIT. See [LICENSE](LICENSE).