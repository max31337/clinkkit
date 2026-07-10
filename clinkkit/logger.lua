--------------------------------------------------------------------------------
-- logger.lua
--
-- Minimal leveled logger for ClinkKit. Writes to Clink's log via
-- clink.debugprint() (safe, never throws) and optionally to stdout when
-- verbose_logging is enabled in config.lua.
--
-- Levels (low -> high verbosity): OFF, WARN, INFO, DEBUG
--------------------------------------------------------------------------------

local logger = {}

local LEVELS = { OFF = 0, WARN = 1, INFO = 2, DEBUG = 3 }
logger.LEVELS = LEVELS

-- current_level is set by history_guard.lua after config.lua loads, to avoid
-- a hard require() cycle between config.lua and logger.lua.
local current_level = LEVELS.WARN

function logger.set_level(level_name)
    local lvl = LEVELS[tostring(level_name or "WARN"):upper()]
    current_level = lvl or LEVELS.WARN
end

local function emit(prefix, fmt, ...)
    -- pcall guards against a bad format string ever crashing Clink.
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        msg = tostring(fmt)
    end
    local line = ("[ClinkKit][%s] %s"):format(prefix, msg)

    -- clink.debugprint is always safe to call; it writes to clink.log.
    if clink and clink.debugprint then
        pcall(clink.debugprint, line)
    end
end

function logger.debug(fmt, ...)
    if current_level >= LEVELS.DEBUG then emit("DEBUG", fmt, ...) end
end

function logger.info(fmt, ...)
    if current_level >= LEVELS.INFO then emit("INFO", fmt, ...) end
end

function logger.warn(fmt, ...)
    if current_level >= LEVELS.WARN then emit("WARN", fmt, ...) end
end

-- User-facing message (the "Did you mean" suggestion). Always printed
-- regardless of log level, unless silent mode is requested by the caller.
function logger.notice(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    -- print() goes to the actual terminal the user sees.
    print(msg)
end

return logger
