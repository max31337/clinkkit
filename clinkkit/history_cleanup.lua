--------------------------------------------------------------------------------
-- history_cleanup.lua
--
-- Scans the EXISTING persisted Clink history file and strips out entries
-- that HistoryGuard would have rejected (unknown executables, keyboard
-- smashes, subcommand/option typos, obsolete exact duplicates), then
-- compacts the file.
--
-- Clink's history file format (documented by the maintainer here:
-- https://github.com/chrisant996/clink/discussions/229):
--   - First line begins with "|CTAG" and must be preserved as-is.
--   - Every other line is one history entry.
--   - A line that starts with "|" is treated as already-deleted.
--   - `clink history compact` physically removes those "|"-prefixed lines.
-- This module edits the file directly using that same convention, so the
-- results are 100% compatible with Clink's own `history compact` command
-- (which you can also run afterwards from the prompt, belt-and-suspenders).
--
-- SAFETY: a timestamped .bak copy of the history file is always written
-- before any modification, and nothing is touched unless
-- hg.enable_cleanup is true.
--------------------------------------------------------------------------------

local config = require("config")
local logger = require("logger")
local utils = require("utils")

local history_cleanup = {}

-- The cleanup shortcut can be invoked repeatedly in one Clink session.  Keep
-- its decisions in memory so an unchanged history entry is evaluated only
-- once.  This matters when the optional executable and flag checks are on,
-- since those can invoke `where` and command help discovery.
local evaluation_cache = { key = nil, entries = {} }

local function cleanup_config_key()
    -- Include every evaluator setting that can alter a cleanup decision.  A
    -- changed setting naturally starts a fresh cache without needing a reload.
    local names = {
        "hg.typo_detect", "hg.key_smash", "hg.unknown_exe",
        "hg.subcmd_detect", "hg.strict_subcommands", "hg.option_detect",
        "hg.max_distance", "hg.whitelist", "hg.blacklist", "hg.cache_days",
        "hg.cleanup_unknown_exe", "hg.cleanup_option_detect",
    }
    local values = {}
    for _, name in ipairs(names) do
        values[#values + 1] = name .. "=" .. tostring(settings.get(name))
    end
    return table.concat(values, "\n")
end


--------------------------------------------------------------------------------
local function locate_history_file()
    -- Prefer an explicit override, then fall back to Clink's documented
    -- default profile location. If your profile directory is customized
    -- (via --profile or %CLINK_PROFILE%), set that same env var before
    -- starting Clink and this will pick it up automatically.
    local profile = os.getenv("CLINK_PROFILE")
    if profile and profile ~= "" then
        return profile .. "\\clink_history"
    end
    local localappdata = os.getenv("LOCALAPPDATA")
    if not localappdata then return nil end
    return localappdata .. "\\clink\\clink_history"
end

local function get_backups_folder()
    local localappdata = os.getenv("LOCALAPPDATA")
    if not localappdata then return nil end
    return localappdata .. "\\clink\\historyguard_backups"
end

--- Organizes existing backup files into the backups folder
local function organize_old_backups()
    -- This function is not executed during startup to avoid shell initialization issues.
    -- It can be called manually if needed.
    -- For now, new backups are saved directly to the folder, and old backups
    -- should be manually moved if desired.
end

local function backup_file(path)
    local content = utils.read_file(path)
    if not content then return false end
    
    local backups_folder = get_backups_folder()
    if backups_folder then
        utils.ensure_dir(backups_folder)
        local stamp = os.date("%Y%m%d_%H%M%S")
        local filename = "clink_history.bak_" .. stamp
        return utils.write_file(backups_folder .. "\\" .. filename, content)
    else
        -- Fallback to root directory if we can't get backups folder
        local stamp = os.date("%Y%m%d_%H%M%S")
        return utils.write_file(path .. ".bak_" .. stamp, content)
    end
end

--------------------------------------------------------------------------------
--- Runs the cleanup pass.
-- opts.dry_run: if true, reports what WOULD be removed without writing.
-- opts.quiet:   if true, suppresses per-line print() output.
function history_cleanup.run(opts)
    opts = opts or {}

    --------------------------------------------------------------------------------
    -- Cleanup feature disabled
    --------------------------------------------------------------------------------

    if not config.enable_cleanup then
        logger.warn("HistoryGuard cleanup is disabled.")

        return {
            removed = 0,
            kept = 0,
            aborted = true,
            reason = "History cleanup is currently disabled. Enable 'hg.enable_cleanup' to use this feature."
        }
    end

    --------------------------------------------------------------------------------
    -- HistoryGuard engine unavailable
    --------------------------------------------------------------------------------
    local ok, evaluator = pcall(require, "history_evaluator")

    if not ok then
        logger.warn("Failed to load HistoryGuard evaluator: %s", tostring(evaluator))

        return {
            removed = 0,
            kept = 0,
            aborted = true,
            reason =
                "Failed to initialize the HistoryGuard evaluator.\n\n"
                .. tostring(evaluator)
        }
    end

    if type(evaluator.evaluate_line) ~= "function" then
        logger.warn("HistoryGuard evaluator is missing evaluate_line().")

        return {
            removed = 0,
            kept = 0,
            aborted = true,
            reason =
                "HistoryGuard evaluator is incomplete.\n\n"
                .. "evaluate_line() was not found."
        }
    end

    --------------------------------------------------------------------------------
    -- History file not found
    --------------------------------------------------------------------------------

    local path = locate_history_file()

    if not path then
        logger.warn("Unable to locate Clink history file.")

        return {
            removed = 0,
            kept = 0,
            aborted = true,
            reason = "Unable to locate your Clink history file.\n\n"
                .. "Verify that Clink is installed correctly and that LOCALAPPDATA or CLINK_PROFILE is configured."
        }
    end

    --------------------------------------------------------------------------------
    -- Unable to read history
    --------------------------------------------------------------------------------

    local content = utils.read_file(path)

    if not content then
        logger.warn("Unable to read history file: %s", path)

        return {
            removed = 0,
            kept = 0,
            aborted = true,
            reason = "The Clink history file could not be opened.\n\n"
                .. "Path: " .. path
        }
    end

    --------------------------------------------------------------------------------
    -- Backup failed
    --------------------------------------------------------------------------------

    if not opts.dry_run then
        if not backup_file(path) then
            logger.warn("Failed to create backup.")

            return {
                removed = 0,
                kept = 0,
                aborted = true,
                reason = "Cleanup was cancelled because a backup could not be created.\n\n"
                    .. "Your history remains unchanged for safety."
            }
        end
    end


    -- Save original config and apply cleanup-friendly settings for speed
    local orig_unknown_exe = config.enable_unknown_executable_detection
    local orig_option_detect = config.enable_option_detection
    
    if not config.cleanup_unknown_exe then
        config.enable_unknown_executable_detection = false
    end
    if not config.cleanup_option_detect then
        config.enable_option_detection = false
    end

    local cache_key = cleanup_config_key()
    if evaluation_cache.key ~= cache_key then
        evaluation_cache.key = cache_key
        evaluation_cache.entries = {}
    end

    local out_lines = {}
    local seen_exact = {}
    local removed, kept = 0, 0

    local first = true
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        if first then
            -- Preserve the |CTAG header (or whatever the first line is)
            -- untouched, exactly as Clink wrote it.
            table.insert(out_lines, line)
            first = false
        elseif line == "" then
            -- skip trailing blank lines
        elseif line:sub(1, 1) == "|" then
            -- Already-deleted line; drop it (compaction).
            removed = removed + 1
        else
            -- Strip off an optional leading timestamp field if present
            -- (history.time_stamp adds one); HistoryGuard only cares about
            -- the command text itself.
            local command_text = line:gsub("^%d+%s+", "")
            local duplicate = seen_exact[command_text]

            local cached = evaluation_cache.entries[command_text]
            local eval_ok, keep
            if cached then
                eval_ok, keep = cached.eval_ok, cached.keep
            else
                eval_ok, keep = pcall(evaluator.evaluate_line, command_text)
                -- Evaluation errors are deliberately not cached.  That
                -- preserves fail-open behavior if an intermittent issue
                -- resolves before the next cleanup run.
                if eval_ok then
                    evaluation_cache.entries[command_text] = {
                        eval_ok = eval_ok,
                        keep = keep,
                    }
                end
            end

            if not eval_ok then
                -- Fail open: never destroy a line we couldn't evaluate.
                table.insert(out_lines, line)
                kept = kept + 1
            elseif keep and not duplicate then
                table.insert(out_lines, line)
                seen_exact[command_text] = true
                kept = kept + 1
            else
                removed = removed + 1
                if not opts.quiet then
                    print("HistoryGuard cleanup: removing -> " .. command_text)
                end
            end
        end
    end

    local wrote = true
    if not opts.dry_run then
        wrote = utils.write_file(path, table.concat(out_lines, "\n") .. "\n")
    end

    if not wrote then
        return {
            removed = removed,
            kept = kept,
            aborted = true,
            reason = "Failed to save the cleaned history file."
        }
    end

    -- Restore original config settings
    config.enable_unknown_executable_detection = orig_unknown_exe
    config.enable_option_detection = orig_option_detect

    local summary = string.format(
        "HistoryGuard cleanup: %d removed, %d kept%s",
        removed, kept, opts.dry_run and " (dry run, nothing written)" or "")
    if not opts.quiet then print(summary) end
    logger.info(summary)

    return { removed = removed, kept = kept, aborted = false }
end

--- Public function to organize existing old backups
function history_cleanup.organize_old_backups()
    organize_old_backups()
end

return history_cleanup
