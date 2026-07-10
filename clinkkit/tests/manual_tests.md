# HistoryGuard manual test guide

HistoryGuard is ClinkKit's current feature. This guide verifies its real Clink behavior; future ClinkKit modules, including aliases and utilities, will add their own test sections.

Use a disposable or backed-up Clink profile for cleanup tests. Live filtering does not prevent commands from executing, but cleanup changes the persisted history file.

## Automated baseline

From `clinkkit\tests`:

```cmd
lua run_tests.lua
```

The suite must finish with `0 failed`. The number of passing assertions is intentionally not fixed and may increase with coverage.

## Load the scripts

Install both `00_clinkkit.lua` and the `clinkkit` directory in your active Clink profile. Start a new CMD session or press `Ctrl-X`, then `Ctrl-R`.

Confirm that settings are registered:

```cmd
clink set hg.max_distance
clink set hg.strict_subcommands
```

For diagnostics:

```cmd
clink set hg.verbose_logging DEBUG
```

After the current scripts have loaded, `clink set hg.* ...` applies the changed HistoryGuard configuration at the next prompt. The default Clink log is `%LOCALAPPDATA%\clink\clink.log`.

## Live filtering

Run each command at an ordinary Clink prompt, then inspect history with `history`, `F7`, or reverse search.

| Input | Expected execution | Expected history result |
|---|---|---|
| `git status` | Git runs normally. | Kept. |
| `git stauts` | Git reports its usual error. | Excluded and suggests `git status` when `hg.max_distance` is at least `2`. |
| `gitt status` | CMD reports its usual error. | Excluded, normally with a `git` suggestion. |
| `;;;;` | CMD handles it normally. | Excluded as punctuation-only. |
| `qqqqqq` | CMD reports its usual error. | Excluded as a keyboard smash. |
| `cls` | CMD clears the screen. | Excluded silently because it is blacklisted by default. |

The command must always execute. Only HistoryGuard's saved-history decision changes.

## Typo settings and strict mode

Set normal suggestion behavior:

```cmd
clink set hg.typo_detect true
clink set hg.max_distance 2
```

`stauts` is a transposition of letters in `status`; standard Levenshtein distance treats it as two edits. With a distance of `1`, it is intentionally not treated as a typo.

Enable strict subcommands:

```cmd
clink set hg.strict_subcommands true
```

Now run:

```cmd
git asdfgh
git status
```

The first command should be excluded as an unrecognized subcommand and the second should be kept. If you use Git aliases, external Git commands, or plugin commands, turn strict mode off and confirm those commands stay in history:

```cmd
clink set hg.strict_subcommands false
```

Turn off typo checks temporarily:

```cmd
clink set hg.typo_detect false
```

`git stauts` should now be kept unless another rule excludes it. Restore typo checking afterward:

```cmd
clink set hg.typo_detect true
```

## Cleanup

Enable the cleanup hotkey:

```cmd
clink set hg.enable_cleanup true
clink set hg.enable_cleanup_keybinding true
```

Reload scripts with `Ctrl-X`, then `Ctrl-R`. Press `Alt-Ctrl-H`.

Verify that:

- A timestamped backup appears under `%LOCALAPPDATA%\clink\historyguard_backups\`.
- Entries rejected by active cleanup rules are removed.
- Exact duplicate entries are removed.
- Valid entries remain and preserve their order.

For a no-write test from a Lua debugging context:

```lua
require("history_cleanup").run({ dry_run = true })
```

Verify the reported removals and confirm no backup or history-file write occurred.

### Full cleanup checks

Enable the slow checks only when you want cleanup to evaluate them:

```cmd
clink set hg.cleanup_unknown_exe true
clink set hg.cleanup_option_detect true
```

The first run may inspect executables and command help. Run the hotkey again without changing the history; unchanged entries should reuse the in-memory cleanup cache during the same CMD session.

## Fail-open behavior

Only in a disposable copy, temporarily add this as the first statement in `evaluate_line()` in `history_evaluator.lua`:

```lua
error("manual fail-open test")
```

Reload scripts and enter a normal command. Confirm that it still executes and is kept in history, with a warning in `clink.log`. Remove the temporary line and reload again.
