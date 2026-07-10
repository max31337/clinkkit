# HistoryGuard — Test Guide

HistoryGuard is currently the primary feature of **ClinkKit**. This guide
covers both automated and manual verification of HistoryGuard's behavior.
As ClinkKit grows to include additional features (such as aliases and
command-line utilities), this guide will be expanded with feature-specific
test sections.

---

## 1. Automated Unit Tests

The automated test runner (`run_tests.lua`) executes the complete
HistoryGuard test suite using a standard Lua interpreter, so **Clink is not
required**.

The test suite currently verifies:

- Levenshtein distance calculations
- Tokenization and string utilities
- Keyboard-smash and punctuation detection
- The complete HistoryGuard decision pipeline
- Empty and blank-line handling
- Executable discovery
- Command cache generation
- Configuration loading and reloading
- Logger functionality
- Integration scenarios
- Stress and performance tests
- Edge cases and boundary conditions
- Suggestion quality
- Fail-open error handling

To run the suite:

```cmd
cd clinkkit\tests
lua run_tests.lua
```

A successful run finishes with output similar to:

```text
--------------------------------------------------
ClinkKit Test Suite
==================================================
Running HistoryGuard Unit Tests...
--------------------------------------------------
...
--------------------------------------------------
Testing completed: 121 passed, 0 failed
--------------------------------------------------
```

The exact number of passing tests may increase as new test cases are added,
but **all tests should pass with 0 failures**.

---

## 2. Manual Test Setup

Enable debugging before running the integration tests:

```cmd
clink set lua.debug true
clink set hg.verbose_logging DEBUG
```

Restart CMD (or press `Ctrl-X Ctrl-R`) so the updated settings and scripts
are reloaded.

---

## 3. Direct Pipeline Tests

These tests verify the decision engine directly without modifying your
command history.

Open the Lua debugger (`pause()` from any loaded script, or another Lua
debug entry point) and run:

```lua
local evaluator = require("history_evaluator")

print(evaluator.evaluate_line("git status"))
print(evaluator.evaluate_line("git stauts"))
print(evaluator.evaluate_line("asdfasdf"))
print(evaluator.evaluate_line("rg --help"))
print(evaluator.evaluate_line("rg --hlep"))
print(evaluator.evaluate_line(";;;;"))
print(evaluator.evaluate_line("qqqqqq"))
print(evaluator.evaluate_line("gitt status"))
print(evaluator.evaluate_line("cls"))
```

Expected results:

| Input | Expected Result |
|--------|-----------------|
| `git status` | `true` |
| `git stauts` | `false`, `"subcommand-typo"`, `"git status"` |
| `asdfasdf` | `false`, `"keyboard-smash"` |
| `rg --help` | `true` |
| `rg --hlep` | `false`, `"option-typo"`, `"rg --help"` |
| `;;;;` | `false`, `"punctuation-only"` |
| `qqqqqq` | `false`, `"keyboard-smash"` |
| `gitt status` | `false`, `"unknown-executable"`, `"git"` |
| `cls` | `false`, `"blacklisted"` |

If any result differs:

- Verify `hg.max_distance` (default: `2`).
- Verify the command exists on your `PATH`.
- Check the generated command cache.
- Review `clink.log` with `hg.verbose_logging=DEBUG`.

---

## 4. Live End-to-End Tests

At a normal Clink prompt, execute the following commands and then inspect
your history (`history` or `F7`).

| Command Typed | Executes? | Saved to History? |
|---------------|-----------|-------------------|
| `git status` | ✅ Yes | ✅ Yes |
| `git stauts` | ❌ Git reports unknown subcommand | ❌ No |
| `asdfasdf` | ❌ CMD reports unknown command | ❌ No |
| `rg --help` | ✅ Yes | ✅ Yes |
| `rg --hlep` | ❌ Ripgrep reports invalid flag | ❌ No |
| `;;;;` | ❌ CMD syntax error | ❌ No |
| `cls` | ✅ Clears screen | ❌ No |

Verify that HistoryGuard **never prevents the command from executing**.
Only the history entry should be rejected.

---

## 5. Cleanup Utility Tests

1. Manually add several invalid commands to your `clink_history` file.

2. Bind the cleanup command in `.inputrc`:

```
M-C-h: "luafunc:historyguard_run_cleanup"
```

3. Press **Alt+Ctrl+H**, or run:

```lua
require("history_cleanup").run({
    dry_run = true
})
```

Verify that:

- Invalid entries are reported.
- Nothing is modified during a dry run.

4. Run cleanup again without `dry_run`.

Verify that:

- A timestamped backup is created.
- Invalid entries are removed.
- Valid history entries remain untouched.
- Entry ordering is preserved.

5. Finally run:

```cmd
history compact
```

Verify that the history file is physically compacted and no deleted entries
remain.

---

## 6. Configuration Tests

Disable unknown executable detection:

```cmd
clink set hg.unknown_exe false
```

Verify that commands such as:

```cmd
asdfasdf
```

are now written to history.

Re-enable the setting afterward:

```cmd
clink set hg.unknown_exe true
```

Repeat similar tests for the remaining configuration options to ensure each
feature can be independently enabled and disabled.

---

## 7. Fail-Open Verification

HistoryGuard is designed to **fail open**. Internal errors should never
prevent the shell from functioning normally.

Temporarily insert the following line at the beginning of
`evaluate_line()` inside `history_evaluator.lua`:

```lua
error("test")
```

Reload Clink and verify that:

- Commands still execute normally.
- Commands are still written to history.
- A warning is logged to `clink.log`.

Remove the temporary test afterward.

---

## Expected Result

A successful verification should demonstrate that:

- All automated tests pass.
- Valid commands are preserved.
- Invalid commands are rejected from history.
- Suggestions are generated correctly.
- Cleanup removes previously stored invalid history entries.
- Configuration options behave independently.
- Any unexpected internal error causes HistoryGuard to fail open rather than interfere with the shell.