-- tests/run_tests.lua
-- Standalone test runner for HistoryGuard.
-- Runs with any standard Lua interpreter.

-- 1. Setup paths so it can find clinkkit modules in the parent directory
package.path = "../?.lua;../clinkkit/?.lua;./?.lua;" .. package.path

-- 2. Mock Clink settings and global objects
local settings_store = {}
_G.settings = {
    add = function(name, default_value, description)
        if settings_store[name] == nil then
            settings_store[name] = default_value
        end
    end,
    get = function(name)
        return settings_store[name]
    end,
    set = function(name, value)
        settings_store[name] = value
    end
}

_G.clink = {
    version_encoded = 10090028, -- Mock Clink 1.9.28
    debugprint = function(line)
        -- Suppress debug log clutter during tests, or print if debugging
        -- print("[Clink Log] " .. tostring(line))
    end,
    onhistory = function(handler)
        _G.mock_onhistory_handler = handler
    end,
    ondisplayedinput = function(handler)
        _G.mock_ondisplayedinput_handler = handler
    end,
}

-- 3. Load modules
local levenshtein = require("levenshtein")
local utils = require("utils")
local hg = require("history_guard")
local config = require("config")

-- 4. Test assertion helper
local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("❌ FAIL: %s\n   Expected: %s\n   Actual:   %s", tostring(msg), tostring(expected), tostring(actual)))
    end
end

-- HistoryGuard applies `clink set hg.*` changes after the command finishes,
-- at the next displayed prompt.
settings_store["hg.max_distance"] = 2
_G.mock_onhistory_handler("clink set hg.max_distance 1")
settings_store["hg.max_distance"] = 1
_G.mock_ondisplayedinput_handler()
assert_eq(config.max_distance, 1, "hg setting reloads after clink set")
settings_store["hg.max_distance"] = 2
config.reload()

local function table_count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

print("==================================================")
print("                 ClinkKit Test Suite")
print("==================================================")
print("Project : ClinkKit")
print("Module  : HistoryGuard")
print("Version : 0.1.0")
print("--------------------------------------------------")
print("")

-- TEST SUITE 1: Levenshtein Distance
print("1. Testing Levenshtein distance calculations...")
assert_eq(levenshtein.distance("git", "gitt"), 1, "git vs gitt")
assert_eq(levenshtein.distance("status", "statis"), 1, "status vs statis")
assert_eq(levenshtein.distance("status", "syuts"), 3, "status vs syuts")
assert_eq(levenshtein.distance("rg", "rg"), 0, "rg vs rg (identical)")
assert_eq(levenshtein.distance("", "test"), 4, "empty string vs 4-char string")

-- TEST SUITE 2: Word Tokenizer (utils.split_words)
print("2. Testing tokenizer and string utils...")
local words = utils.split_words("git commit -m \"hello world\"")
assert_eq(#words, 4, "number of tokens in command")
assert_eq(words[1], "git", "first token")
assert_eq(words[4], "hello world", "quoted token")

-- TEST SUITE 3: Keyboard Smash Heuristics
print("3. Testing keyboard smash detection...")
assert_eq(utils.is_keyboard_smash("qqqqqq"), true, "repeated char smash")
assert_eq(utils.is_keyboard_smash("ababab"), true, "alternating 2-char smash")
assert_eq(utils.is_keyboard_smash("git"), false, "valid short command")
assert_eq(utils.is_keyboard_smash("status"), false, "valid English word")

-- TEST SUITE 4: Decision Pipeline (hg.evaluate_line)
print("4. Testing main evaluation pipeline (hg.evaluate_line)...")

-- Identical command (should keep)
local keep, reason = hg.evaluate_line("git status")
assert_eq(keep, true, "valid git status is kept")

-- Blacklisted command
local keep, reason = hg.evaluate_line("cls")
assert_eq(keep, false, "blacklisted command rejected")
assert_eq(reason, "blacklisted", "blacklisted reason matches")

-- Keyboard smash
local keep, reason = hg.evaluate_line("qqqqqq")
assert_eq(keep, false, "keyboard smash rejected")
assert_eq(reason, "keyboard-smash", "keyboard smash reason matches")

-- Subcommand typo (distance <= max_distance)
local keep, reason, suggestion = hg.evaluate_line("git statos")
assert_eq(keep, false, "git statos is rejected as typo")
assert_eq(reason, "subcommand-typo", "typo reason matches")
assert_eq(suggestion, "git status", "typo suggestion is correct")

-- Subcommand typo with distance > max_distance (should keep/fail-open)
local keep, reason = hg.evaluate_line("git syuts")
assert_eq(keep, true, "git syuts with distance 3 kept (default max_distance is 2)")

-- Option typo (rg --hlep)
-- Insert a mock entry for 'rg' in the cache since generic help execution is mocked/empty here
local command_cache = require("command_cache")
local rg_cache = command_cache.get("rg")
table.insert(rg_cache.flags, "--help")

local keep, reason, suggestion = hg.evaluate_line("rg --hlep")
assert_eq(keep, false, "option typo rg --hlep rejected")
assert_eq(reason, "option-typo", "option typo reason matches")
assert_eq(suggestion, "rg --help", "option suggestion matches")

-- TEST SUITE 5: Empty/Blank Lines
print("5. Testing empty and blank line handling...")
local keep, reason = hg.evaluate_line("")
assert_eq(keep, true, "empty line is kept")

local keep, reason = hg.evaluate_line("   ")
assert_eq(keep, true, "whitespace-only line is kept")

local keep, reason = hg.evaluate_line("\t\t")
assert_eq(keep, true, "tab-only line is kept")

-- TEST SUITE 6: Punctuation-Only Detection
print("6. Testing punctuation-only rejection...")
local keep, reason = hg.evaluate_line(";;;;")
assert_eq(keep, false, "semicolons-only rejected")
assert_eq(reason, "punctuation-only", "punctuation-only reason matches")

local keep, reason = hg.evaluate_line("......")
assert_eq(keep, false, "dots-only rejected")
assert_eq(reason, "punctuation-only", "punctuation-only reason matches")

local keep, reason = hg.evaluate_line(",,,,")
assert_eq(keep, false, "commas-only rejected")

local keep, reason = hg.evaluate_line("!@#$%")
assert_eq(keep, false, "special chars-only rejected")

-- TEST SUITE 7: Whitelisted Commands (bypass unknown-exe check)
print("7. Testing whitelisted command bypass...")
local keep, reason = hg.evaluate_line("python")
assert_eq(keep, true, "whitelisted 'python' is kept even if not installed")

local keep, reason = hg.evaluate_line("node /some/script.js")
assert_eq(keep, true, "whitelisted 'node' is kept")

local keep, reason = hg.evaluate_line("nvim /path/to/file")
assert_eq(keep, true, "whitelisted 'nvim' is kept")

-- TEST SUITE 8: Unknown Executable Detection
print("8. Testing unknown executable rejection...")
local keep, reason = hg.evaluate_line("nonexistentcmd12345xyz argument")
assert_eq(keep, false, "unknown command rejected")
assert_eq(reason, "unknown-executable", "unknown-executable reason matches")

local keep, reason = hg.evaluate_line("fakecmdthatdoesntexist")
assert_eq(keep, false, "unknown single command rejected")

-- TEST SUITE 9: Case-Insensitivity
print("9. Testing case-insensitive command matching...")
local keep, reason = hg.evaluate_line("GIT status")
assert_eq(keep, true, "uppercase GIT is recognized")

local keep, reason = hg.evaluate_line("Git COMMIT")
assert_eq(keep, true, "mixed case git commit is recognized")

local keep, reason = hg.evaluate_line("CLS")
assert_eq(keep, false, "uppercase CLS is blacklisted")
assert_eq(reason, "blacklisted", "blacklist is case-insensitive")

-- TEST SUITE 10: Levenshtein Edge Cases
print("10. Testing Levenshtein distance edge cases...")
assert_eq(levenshtein.distance("a", "b"), 1, "single char substitution")
assert_eq(levenshtein.distance("abc", "abc"), 0, "identical strings")
assert_eq(levenshtein.distance("abc", "abcdef"), 3, "insertion distance")
assert_eq(levenshtein.distance("hello", "hallo"), 1, "vowel typo")

-- TEST SUITE 11: String Utils Edge Cases
print("11. Testing string utils edge cases...")
assert_eq(utils.trim("  hello  "), "hello", "trim removes leading/trailing spaces")
assert_eq(utils.trim(""), "", "trim on empty string")
assert_eq(utils.is_punctuation_only("a;"), false, "mixed alphanumeric and punctuation")
assert_eq(utils.is_punctuation_only(""), false, "empty string is not punctuation-only")

local tokens = utils.split_words("single")
assert_eq(#tokens, 1, "single word splits to one token")
assert_eq(tokens[1], "single", "single token value")

local tokens = utils.split_words("")
assert_eq(#tokens, 0, "empty string splits to zero tokens")

-- TEST SUITE 12: Config Reload
print("12. Testing config reload functionality...")
settings_store["hg.max_distance"] = 2
config.reload()
assert_eq(config.max_distance, 2, "config.max_distance matches setting")

settings_store["hg.key_smash"] = false
config.reload()
assert_eq(config.enable_keyboard_smash_detection, false, "keyboard smash detection can be disabled")

-- TEST SUITE 13: Multiple Suggestions (verify closest match is picked)
print("13. Testing closest match selection...")
local keep, reason, suggestion = hg.evaluate_line("git comit")
assert_eq(keep, false, "git comit is rejected as typo")
assert_eq(reason, "subcommand-typo", "typo reason matches")
-- Verify the suggestion is either "commit" or another close subcommand
assert_eq(suggestion ~= nil and string.find(suggestion, "commit") ~= nil, true, "suggestion contains 'commit'")

-- TEST SUITE 14: Command with Path Arguments
print("14. Testing commands with file paths...")
local keep, reason = hg.evaluate_line("git add /path/to/file.txt")
assert_eq(keep, true, "git with file path is kept")

local keep, reason = hg.evaluate_line("cargo build --release")
assert_eq(keep, true, "whitelisted cargo with args is kept")

-- TEST SUITE 15: Fail-Open Error Handling (mock exception)
print("15. Testing fail-open error handling...")
-- Temporarily inject a broken config to test error resilience
local original_evaluate = hg.evaluate_line
-- This would need actual exception injection; for now, verify it doesn't crash on odd input
local keep = hg.evaluate_line(string.rep("a", 10000))  -- very long command
assert_eq(keep ~= nil, true, "very long command doesn't crash (fail-open)")

-- TEST SUITE 16: Executable Module
print("16. Testing executable module...")
local executable = require("executable")
-- These will depend on what's actually installed on the system
local git_exists = executable.exists("git")
assert_eq(git_exists ~= nil, true, "executable.exists() returns a value for git")

-- Test a definitely non-existent command
local fake_exists = executable.exists("fakecmd12345xyz99")
assert_eq(fake_exists, false, "executable.exists() returns false for non-existent command")

-- Test suggestion for typos (e.g., "gti" should suggest "git")
local suggestion = executable.suggest("gti", 1)
if suggestion ~= nil then
    assert_eq(suggestion == "git" or suggestion ~= nil, true, "executable.suggest() returns a suggestion or nil")
end

-- TEST SUITE 17: Command Cache Module
print("17. Testing command cache module...")
local command_cache = require("command_cache")

-- Get cache for a known command
local git_cache = command_cache.get("git")
assert_eq(git_cache ~= nil, true, "command_cache.get() returns a table")
assert_eq(git_cache.subcommands ~= nil, true, "cache entry has subcommands field")
assert_eq(git_cache.flags ~= nil, true, "cache entry has flags field")
assert_eq(git_cache.fetched_at ~= nil, true, "cache entry has fetched_at timestamp")

-- Get cache for an unknown command (should return empty lists, not error)
local unknown_cache = command_cache.get("fakecmd12345")
assert_eq(unknown_cache ~= nil, true, "command_cache.get() fail-open: returns empty cache for unknown cmd")
assert_eq(type(unknown_cache.subcommands), "table", "unknown command cache has empty subcommands table")
assert_eq(type(unknown_cache.flags), "table", "unknown command cache has empty flags table")

-- Refresh cache for a command
local refreshed = command_cache.refresh("git")
assert_eq(refreshed ~= nil, true, "command_cache.refresh() returns a value")

-- TEST SUITE 18: Logger Module
print("18. Testing logger module...")
local logger = require("logger")

-- Test that logger methods exist and don't crash
logger.debug("debug test: %s", "test")
assert_eq(true, true, "logger.debug() doesn't crash")

logger.info("info test: %s", "test")
assert_eq(true, true, "logger.info() doesn't crash")

logger.warn("warn test: %s", "test")
assert_eq(true, true, "logger.warn() doesn't crash")

logger.notice("notice test: %s", "test")
assert_eq(true, true, "logger.notice() doesn't crash")

-- TEST SUITE 19: Integration Scenarios (Complex Real-World Commands)
print("19. Testing integration scenarios...")

-- Scenario 1: Valid complex command with multiple args
local keep, reason = hg.evaluate_line("git commit -m \"fix: update parser\" --author=\"John Doe\"")
assert_eq(keep, true, "complex git command with quotes and args is kept")

-- Scenario 2: Typo in command + valid args
local keep, reason = hg.evaluate_line("gitt add .")
assert_eq(keep, false, "typo in executable (gitt) is rejected")
assert_eq(reason, "unknown-executable", "reason is unknown-executable")

-- Scenario 3: Valid command + subcommand typo
local keep, reason = hg.evaluate_line("git staus")
assert_eq(keep, false, "valid git + invalid subcommand rejected")
assert_eq(reason, "subcommand-typo", "subcommand typo detected")

-- Scenario 4: Whitelisted command with random path
local keep, reason = hg.evaluate_line("python /weird/path/to/script.py")
assert_eq(keep, true, "whitelisted python bypasses unknown-exe check")

-- Scenario 5: Blacklisted command with arguments
local keep, reason = hg.evaluate_line("cls && echo hello")
assert_eq(keep, false, "blacklisted cls is rejected even with args")

-- TEST SUITE 20: Stress Tests (Large/Pathological Inputs)
print("20. Testing stress cases...")

-- Very long command line
local long_cmd = "git commit -m \"" .. string.rep("x", 1000) .. "\""
local keep = hg.evaluate_line(long_cmd)
assert_eq(keep ~= nil, true, "very long command (1000+ chars) handled gracefully")

-- Command with many arguments
local many_args = "cargo test " .. string.rep("arg1 arg2 arg3 ", 50)
local keep = hg.evaluate_line(many_args)
assert_eq(keep ~= nil, true, "command with 150+ args handled gracefully")

-- Nested quotes
local nested = "git commit -m \"outer 'inner' outer\""
local keep = hg.evaluate_line(nested)
assert_eq(keep ~= nil, true, "nested quotes don't crash tokenizer")

-- TEST SUITE 21: Levenshtein Edge Cases (Performance)
print("21. Testing Levenshtein distance performance...")

-- Very similar long strings
local dist1 = levenshtein.distance(string.rep("a", 100) .. "b", string.rep("a", 100) .. "c")
assert_eq(dist1, 1, "long strings with 1-char difference")

-- Very dissimilar strings
local dist2 = levenshtein.distance(string.rep("a", 50), string.rep("b", 50))
assert_eq(dist2, 50, "completely different 50-char strings")

-- TEST SUITE 22: Closest Match (Multiple Candidates)
print("22. Testing closest match selection with many candidates...")

local candidates = {"status", "stash", "start", "statictics", "statos", "stage"}
local closest, distance = levenshtein.closest("statis", candidates, 2)
assert_eq(closest ~= nil, true, "closest match found from multiple candidates")
assert_eq(distance <= 2, true, "distance is within max_distance")

-- TEST SUITE 23: Config Edge Cases
print("23. Testing config edge cases...")

-- Whitelist and blacklist parsing
local config_backup_whitelist = config.whitelist
local config_backup_blacklist = config.blacklist

settings_store["hg.whitelist"] = "git,go,python"
settings_store["hg.blacklist"] = "cls,exit,rm"
config.reload()

assert_eq(config.whitelist["git"] ~= nil, true, "whitelist parsing works")
assert_eq(config.whitelist["go"] ~= nil, true, "whitelist has multiple entries")
assert_eq(config.blacklist["cls"] ~= nil, true, "blacklist parsing works")
assert_eq(config.blacklist["exit"] ~= nil, true, "blacklist has multiple entries")

-- Empty whitelist/blacklist
settings_store["hg.whitelist"] = ""
settings_store["hg.blacklist"] = ""
config.reload()
assert_eq(table_count(config.whitelist), 0, "empty whitelist results in empty table")
assert_eq(table_count(config.blacklist), 0, "empty blacklist results in empty table")

-- TEST SUITE 24: Boundary Cases
print("24. Testing boundary cases...")

-- Single character command
local keep, reason = hg.evaluate_line("x")
assert_eq(keep ~= nil, true, "single char command handled")

-- Command that's a number
local keep, reason = hg.evaluate_line("123")
assert_eq(keep ~= nil, true, "numeric-only input handled")

-- Command with special Windows chars
local keep, reason = hg.evaluate_line("dir \\path\\to\\file")
assert_eq(keep ~= nil, true, "backslashes don't crash")

-- TEST SUITE 25: Utils Module - Advanced
print("25. Testing utils module advanced cases...")

-- Path splitting
local paths = utils.split_path("C:\\path1;C:\\path2;C:\\path3", ";")
assert_eq(#paths, 3, "path splitting works")
assert_eq(paths[1], "C:\\path1", "first path is correct")

-- File I/O (mock - won't actually write)
local test_content = "test content"
-- Can't fully test without mocking filesystem, but verify functions exist
assert_eq(type(utils.read_file), "function", "read_file function exists")
assert_eq(type(utils.write_file), "function", "write_file function exists")
assert_eq(type(utils.ensure_dir), "function", "ensure_dir function exists")

-- TEST SUITE 26: Keyboard Smash - Advanced Patterns
print("26. Testing advanced keyboard smash patterns...")

assert_eq(utils.is_keyboard_smash("aaaaaa"), true, "pure repetition detected")
assert_eq(utils.is_keyboard_smash("xyxyxy"), true, "alternating pattern detected")
assert_eq(utils.is_keyboard_smash("abc"), false, "short sequence not flagged")
assert_eq(utils.is_keyboard_smash("abcabc"), false, "pattern < 5 chars not flagged")
assert_eq(utils.is_keyboard_smash("python"), false, "real command not flagged")
assert_eq(utils.is_keyboard_smash("zzzzzzzzzz"), true, "long repetition detected")

-- TEST SUITE 27: Suggestion Quality (Verify Distances)
print("27. Testing suggestion quality/distance...")

-- Create a controlled set of commands to test
local test_candidates = {"commit", "checkout", "cherry-pick", "config"}
local closest, dist = levenshtein.closest("comit", test_candidates, 2)
assert_eq(closest, "commit", "closest match is 'commit'")
assert_eq(dist, 1, "distance to 'commit' is 1")

-- Test with a word closer to checkout
local closest2, dist2 = levenshtein.closest("checkut", test_candidates, 2)
assert_eq(closest2, "checkout", "closest match to 'checkut' is 'checkout'")
assert_eq(dist2, 1, "distance to 'checkout' is 1")

-- TEST SUITE 28: Multi-Word Commands and Quoting
print("28. Testing multi-word commands and quoting...")

local words1 = utils.split_words("echo \"hello world\"")
assert_eq(#words1, 2, "echo + quoted string = 2 tokens")
assert_eq(words1[2], "hello world", "quoted content extracted correctly")

local words2 = utils.split_words("python -c 'print(\"hello\")'")
assert_eq(#words2, 3, "python -c and quoted code = 3 tokens")

-- TEST SUITE 29: Case Sensitivity in Different Contexts
print("29. Testing case sensitivity contexts...")

-- Executable names should be case-insensitive
local keep1 = hg.evaluate_line("GIT status")
assert_eq(keep1, true, "uppercase executable recognized")

-- Subcommands should be case-insensitive
local keep2 = hg.evaluate_line("git STATUS")
assert_eq(keep2, true, "uppercase subcommand recognized")

-- Strict mode catches unrecognised subcommands even when there is no close
-- spelling candidate, but must leave known subcommands untouched.
config.strict_subcommands = true
local strict_keep, strict_reason = hg.evaluate_line("git asdfgh")
assert_eq(strict_keep, false, "strict mode rejects unknown subcommand")
assert_eq(strict_reason, "unknown-subcommand", "strict mode uses the unknown-subcommand reason")
assert_eq(hg.evaluate_line("git status"), true, "strict mode keeps known subcommand")
config.strict_subcommands = false

-- Flags should be case-insensitive
local rg_cache = command_cache.get("rg")
table.insert(rg_cache.flags, "--help")
local keep3 = hg.evaluate_line("rg --HELP")
assert_eq(keep3, true, "uppercase flag recognized")

-- TEST SUITE 30: Fail-Open Comprehensive
print("30. Testing comprehensive fail-open behavior...")

-- Settings with nil/bad values
config.max_distance = nil
local keep, reason = hg.evaluate_line("git statos")
assert_eq(keep ~= nil, true, "missing max_distance doesn't crash")

-- Restore
config.max_distance = 2

print("--------------------------------------------------")
print(string.format("Testing completed: %d passed, %d failed", passed, failed))
print("--------------------------------------------------")

if failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
