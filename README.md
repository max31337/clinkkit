# ClinkKit

**ClinkKit** is a modular toolkit for extending **Clink** on Windows CMD with
quality-of-life improvements, productivity tools, and developer utilities.

The first feature included in ClinkKit is **HistoryGuard**, which prevents
typo'd, accidental, and unwanted commands from polluting your persistent
command history while providing tools to clean up existing history.

```
C:\repos> git stauts
HistoryGuard: didn't save to history. Did you mean:  git status
'stauts' is not recognized as an internal or external command...
```

The command still runs (or fails) exactly as CMD would normally handle it.
HistoryGuard only ever changes what gets *saved to history* — it never
blocks or alters execution.

---

## Current Architecture and how it works

```
ClinkKit
│
├── history_guard.lua        Current project entry point
│
├── history_evaluator.lua    Shared evaluation engine
├── history_cleanup.lua      Cleanup utilities
├── commands.lua             Public commands
├── keybindings.lua          Hotkey registration
│
├── config.lua
├── logger.lua
├── utils.lua
├── executable.lua
├── command_cache.lua
└── levenshtein.lua
```

`evaluate_line(line)` lives in `history_evaluator.lua` and serves as the
shared decision engine used by both the live HistoryGuard module and the
history cleanup utility. Keeping the decision logic in one place guarantees
that commands rejected during live execution are evaluated identically during
offline cleanup.

### Decision pipeline (in order)

1. Blank line → always kept (untouched).
2. Blacklisted command → rejected silently.
3. Keyboard-smash / punctuation-only → rejected.
4. Unknown executable (not on PATH, not a CMD builtin, not whitelisted,
   not a doskey alias, not a path) → rejected, with a suggestion if a
   close match exists.
5. Subcommand typo (`git stauts`) → rejected, with suggestion.
6. Option/flag typo (`rg --hlep`) → rejected, with suggestion.
7. Otherwise → kept.

Every step is individually toggleable in config, and **any unexpected
error anywhere in the pipeline causes the line to be kept** (fail-open),
per the project's error-handling requirement — HistoryGuard should never
be the reason your shell misbehaves.

---

## Requirements

- Clink **v1.5.13 or newer** (for `clink.onhistory()`); v1.9.27+ recommended.
  Check your version with `clink --version`.
- Windows CMD with Clink injected (see [chrisant996/clink](https://github.com/chrisant996/clink)).

> **Before relying on this in production**, run the automated test suite
> (`lua run_tests.lua` in the tests folder) or manually verify with the
> step-by-step checklist in `tests/manual_tests.md` against your installed
> Clink version.

---

## Installation

1. Copy the whole `clinkkit/` folder into your Clink scripts directory.
   The simplest option is directly under your Clink profile:
   ```
   %LOCALAPPDATA%\clink\clinkkit\
   ```
   (Find your exact profile directory by running `clink info`.)
2. Restart your CMD session, or press `Ctrl-X Ctrl-R` to reload Lua scripts.
3. Confirm it loaded: `clink set hg.max_distance` should print `2`.

No extra dependencies — pure Lua 5.2, the version Clink embeds.

---

## Configuration

All options are standard Clink settings (`clink set name value`), stored
in your normal `clink_settings` file:

| Setting | Default | Description |
|---|---|---|
| `hg.typo_detect` | `true` | Master switch for typo checks |
| `hg.key_smash` | `true` | `asdfasdf`, `;;;;`, etc. |
| `hg.unknown_exe` | `true` | `asdf`, `gitt`, `pyhton` |
| `hg.subcmd_detect` | `true` | `git stauts` |
| `hg.option_detect` | `true` | `rg --hlep` |
| `hg.enable_cleanup` | `true` | Allows `history_cleanup.lua` to run |
| `hg.max_distance` | `2` | Max Levenshtein distance treated as a typo |
| `hg.whitelist` | `git,go,cargo,python,py,node,npm,pnpm,yarn,dotnet,code,nvim,vim,rg,fd,docker,kubectl,gh` | Comma list, always known-good executables |
| `hg.blacklist` | `cls,history,exit,clear` | Comma list, always excluded from history |
| `hg.verbose_logging` | `WARN` | `OFF`, `WARN`, `INFO`, `DEBUG` |
| `hg.cleanup_on_start` | `false` | Run a cleanup pass on every Clink start |
| `hg.cache_days` | `7` | How often subcommand/flag caches refresh |
| `hg.show_suggestions` | `true` | Print "Did you mean" messages |

### Example: stricter setup

```cmd
clink set hg.max_distance 1
clink set hg.whitelist "git,go,cargo,rg,fd,dotnet"
clink set hg.verbose_logging INFO
```

### Example: quieter setup (typo blocking only, no suggestions)

```cmd
clink set hg.show_suggestions false
clink set hg.option_detect false
```

---

# Project Roadmap

ClinkKit is designed as a collection of independent modules that extend the
Windows CMD experience.

Current modules:

- ✅ HistoryGuard
  - Live history filtering
  - History cleanup
  - Typo detection
  - Keyboard-smash detection

Planned modules include:

- Aliases
  - User-defined aliases
  - Import/export aliases
  - Alias management commands

- Utilities
  - Safe `trash` command
  - `mkcd`
  - File and directory helpers
  - Additional productivity commands

- More extensions as the project evolves.

HistoryGuard currently serves as ClinkKit's entry point because it is the
first implemented feature. As additional modules are added, the project will
be refactored into a lightweight bootstrapper responsible for loading each
feature independently.

---

## Cleaning up existing history

Bind a key in your `.inputrc`:

```
M-C-h: "luafunc:historyguard_run_cleanup"
```

Then press `Alt-Ctrl-H` at any prompt to run cleanup interactively (it
prints every line it removes). A timestamped backup of your
`clink_history` file is always written first (`clink_history.bak_<timestamp>`),
and `hg.enable_cleanup` must be `true`.

You can also call it directly for a dry run, e.g. from the Lua debugger
(`clink set lua.debug true`, then `pause()` a script and evaluate):

```lua
require("history_cleanup").run({ dry_run = true })
```

After cleanup, running `history compact` (a builtin Clink alias for
`clink history compact`) physically shrinks the file.

---

## Limitations

- Subcommand/flag discovery relies on each tool's own `--help`/`help -a`
  output, which is free-form text; discovery uses conservative pattern
  matching and may miss some subcommands/flags for tools with unusual
  help formatting. Extend `DISCOVERY` in `command_cache.lua` to add more
  tools or refine patterns.
- Keyboard-smash detection is intentionally conservative (repeated /
  low-diversity characters only) — the unknown-executable check is the
  real safety net for things like `asdf` or `qqqq`.
- Argument/path typos that aren't the command or first subcommand (e.g.
  `cd my_projets`) are out of scope; catching arbitrary filesystem-path
  typos reliably would require a much larger dictionary/heuristic and
  risks false positives on legitimately new directory names.
- `history_cleanup.lua` edits the `clink_history` file directly using its
  documented `|`-prefix deletion convention. If Clink's internal history
  file format ever changes in a future version, re-verify against
  `clink history --help` / the Saved Command History docs before running
  cleanup on an upgraded install.
- Performance: the executable-existence PATH index is built once per
  session (lazily, on first use) and cached; typo/flag caches persist to
  disk under `%LOCALAPPDATA%\clink\historyguard_cache\`. Interception
  itself does no disk or process I/O on the fast path (whitelisted/known
  commands).

---

# Future Architecture

ClinkKit is intended to evolve into a modular toolkit rather than a single
feature.

The long-term structure is expected to resemble:

```
clinkkit/
│
├── bootstrap.lua
│
├── historyguard/
│   ├── history_guard.lua
│   ├── history_evaluator.lua
│   └── history_cleanup.lua
│
├── aliases/
│
├── utilities/
│   ├── trash.lua
│   ├── mkcd.lua
│   └── ...
│
├── commands/
├── keybindings/
└── shared/
```

Each feature will be independently loadable while sharing common utilities
such as logging, configuration, caching, and helper functions.

---

# Developer Guide

ClinkKit is organized around small, reusable feature modules.

Core principles:

- Each feature should have a single responsibility.
- Shared functionality belongs in reusable modules.
- Features communicate through well-defined public APIs.
- Avoid circular dependencies.
- Fail open whenever possible to avoid interfering with the user's shell.

Current feature modules:

- HistoryGuard

Planned feature modules:

- Aliases
- Utilities
- Additional productivity extensions

---

## Testing

### Automated Tests

Run the complete automated test suite:

```cmd
cd tests
lua run_tests.lua
```

A successful run should produce output similar to:

```text
--------------------------------------------------
Running HistoryGuard Unit Tests...
--------------------------------------------------
...
--------------------------------------------------
Testing completed: 121 passed, 0 failed
--------------------------------------------------
```

The test suite currently contains **121 automated tests** organized into **30 test groups**, covering:

- Levenshtein distance implementation
- Tokenizer and string utility functions
- Keyboard-smash detection
- History evaluation pipeline (`evaluate_line`)
- Empty and blank-line handling
- Punctuation-only detection
- Whitelist and blacklist behavior
- Unknown executable detection
- Case-insensitive command matching
- Configuration loading and reloading
- Command suggestion quality
- Executable discovery
- Command cache generation
- Logger functionality
- Integration scenarios
- Performance and stress tests
- Boundary and edge cases
- Multi-word commands and quoted arguments
- Comprehensive fail-open behavior

A passing test run should report **121 passed, 0 failed**.al-world scenarios, edge cases, stress tests, and error handling

### Manual Verification

See [`tests/manual_tests.md`](tests/manual_tests.md) for an end-to-end
verification checklist covering:

- Live HistoryGuard interception
- Command suggestion behavior
- History cleanup
- Hotkey registration
- Configuration options
- Error handlingation checklist covering live end-to-end behavior and cleanup functionality.

## License

MIT — see [LICENSE](LICENSE).
