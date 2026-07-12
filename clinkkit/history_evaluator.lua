--------------------------------------------------------------------------------
-- history_evaluator.lua
--
-- Shared command evaluation engine used by ClinkKit's history guard feature.
--------------------------------------------------------------------------------

local config = require("config")
local logger = require("logger")

local levenshtein = require("levenshtein")
local utils = require("utils")
local executable = require("executable")
local command_cache = require("command_cache")

local function evaluate_line(raw_line)
    local line = utils.trim(raw_line)
    if line == "" then
        return true
    end

    local words = utils.split_words(line)
    if #words == 0 then
        return true
    end

    local first_word = words[1]
    local first_lower = first_word:lower()

    if config.blacklist[first_lower] then
        logger.debug("blacklisted command '%s' -> rejecting silently", first_word)
        return false, "blacklisted"
    end

    if config.enable_keyboard_smash_detection then
        if utils.is_punctuation_only(line) then
            return false, "punctuation-only"
        end
        if #words == 1 and utils.is_keyboard_smash(first_word) then
            return false, "keyboard-smash"
        end
    end

    local is_whitelisted = config.whitelist[first_lower]

    if config.enable_unknown_executable_detection and not is_whitelisted then
        if not executable.exists(first_word) then
            local suggestion = executable.suggest(first_word, config.max_distance)
            if suggestion then
                return false, "unknown-executable", suggestion
            end
            return false, "unknown-executable"
        end
    end

    if #words < 2 then
        return true
    end

    local second_word = words[2]

    if config.enable_typo_detection
        and config.enable_subcommand_detection
        and not second_word:match("^%-") then
        local cache = command_cache.get(first_lower, config.cache_refresh_days)
        if cache and #cache.subcommands > 0 then
            local exact = false
            for _, sub in ipairs(cache.subcommands) do
                if sub:lower() == second_word:lower() then exact = true break end
            end
            if not exact then
                local suggestion, dist = levenshtein.closest(
                    second_word:lower(), cache.subcommands, config.max_distance)
                if suggestion and dist > 0 then
                    return false, "subcommand-typo", first_word .. " " .. suggestion
                end
                if config.strict_subcommands then
                    return false, "unknown-subcommand"
                end
            end
        end
    end

    if config.enable_typo_detection and config.enable_option_detection then
        local cache = command_cache.get(first_lower, config.cache_refresh_days)
        if cache and #cache.flags > 0 then
            for _, word in ipairs(words) do
                if word:match("^%-%-[%a]") then
                    local exact = false
                    for _, flag in ipairs(cache.flags) do
                        if flag:lower() == word:lower() then exact = true break end
                    end
                    if not exact then
                        local suggestion, dist = levenshtein.closest(
                            word:lower(), cache.flags, config.max_distance)
                        if suggestion and dist > 0 then
                            return false, "option-typo", line:gsub(
                                word:gsub("%p", "%%%1"), suggestion, 1)
                        end
                    end
                end
            end
        end
    end

    return true
end

return {
    evaluate_line = evaluate_line
}