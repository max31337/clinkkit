--------------------------------------------------------------------------------
-- history_guard.lua
--
-- Main entry point for ClinkKit.
--
-- HistoryGuard is currently ClinkKit's primary feature, so this module also
-- serves as the project's entry point. It initializes the HistoryGuard
-- feature, registers the required Clink event handlers, and loads supporting
-- modules such as commands and keybindings.
--
-- As ClinkKit evolves, this file will become a lightweight bootstrapper that
-- loads independent feature modules. See the project README for the planned
-- architecture and feature roadmap.
--
-- HistoryGuard prevents unwanted commands from being written to Clink's
-- history by registering a clink.onhistory() callback.
--
-- IMPORTANT / VERIFY-ON-INSTALL:
-- clink.onhistory() was added in Clink v1.5.13 and, per the official
-- CHANGES log, is "called when the input line has been accepted and is
-- about to be added to history (and optionally cancel adding it)"; since
-- v1.9.27 the handler may also return a string to override what gets
-- saved. This file assumes the common Lua callback convention used
-- elsewhere in Clink's API (return false/nil-with-false to cancel, return
-- a string to replace, return nothing to keep default behavior).
--
-- The first time you install this, run the tests in tests/manual_tests.md
-- to confirm this behavior against your installed Clink version. If the
-- callback contract changes in a future Clink release, only the
-- `on_history_event()` function below should require modification.
--------------------------------------------------------------------------------

if not clink or not clink.version_encoded or clink.version_encoded < 10050013 then
    -- Fail open: without a recent-enough Clink, do nothing rather than error.
    if clink and clink.debugprint then
        clink.debugprint("[ClinkKit] Clink is too old (need >= v1.5.13 for clink.onhistory); ClinkKit disabled.")
    end
    return
end

local config     = require("config")
local logger     = require("logger")
local evaluator = require("history_evaluator")
local evaluate_line = evaluator.evaluate_line
require("commands")

--------------------------------------------------------------------------------
-- Startup integrations
--------------------------------------------------------------------------------

local ok, err = pcall(function()
    require("keybindings").initialize()
end)

if not ok then
    logger.warn("Failed to initialize keybindings: %s", tostring(err))
end

--------------------------------------------------------------------------------
-- clink.onhistory glue
--------------------------------------------------------------------------------

local function on_history_event(line)
    -- Never let a bug here break the user's shell: worst case, keep the
    -- history entry (fail open), per the project's error-handling policy.
    logger.debug("on_history_event called with line: %s", tostring(line))
    local ok, keep, reason, suggestion = pcall(evaluate_line, line)
    if not ok then
        logger.warn("evaluate_line() error: %s -- keeping entry", tostring(keep))
        return
    end

    if keep then
        return -- nil/true: let Clink save the line normally
    end

    logger.info("rejecting history entry (%s): %s", tostring(reason), line)

    if config.show_suggestions and reason ~= "blacklisted" then
        if suggestion then
            logger.notice("HistoryGuard: didn't save to history. Did you mean:  " .. suggestion)
        elseif reason == "keyboard-smash" or reason == "punctuation-only" then
            logger.notice("HistoryGuard: didn't save to history (keyboard smash).")
        elseif reason == "unknown-executable" then
            logger.notice("HistoryGuard: didn't save to history (unrecognized command).")
        elseif reason == "unknown-subcommand" then
            logger.notice("HistoryGuard: didn't save to history (unrecognized subcommand).")
        else
            logger.notice("HistoryGuard: didn't save to history (" .. tostring(reason) .. ").")
        end
    end

    return false
end

clink.onhistory(on_history_event)

logger.info(
    "HistoryGuard loaded (max_distance=%d)",
    config.max_distance
)

    if config.auto_cleanup_on_start
    and config.enable_cleanup then

        local cleanup_scheduled = false

        local function on_prompt_displayed()

            if cleanup_scheduled then
                return
            end

            cleanup_scheduled = true

            local ok, cleanup = pcall(require, "history_cleanup")

            if ok and cleanup and cleanup.run then
                pcall(cleanup.run, {
                    quiet = true
                })
            end
        end

        if clink.ondisplayedinput then
            clink.ondisplayedinput(on_prompt_displayed)
        else
            logger.debug("Automatic startup cleanup is unavailable on this Clink version.")
        end

    end

return {
    evaluate_line = evaluate_line, -- exported for tests/manual_tests.md
}
