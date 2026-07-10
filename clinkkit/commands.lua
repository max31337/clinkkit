--------------------------------------------------------------------------------
-- commands.lua
--
-- Public commands callable from Clink keybindings.
--------------------------------------------------------------------------------

local logger = require("logger")
local commands = {}

function commands.cleanup(rl_buffer)

    local ok, cleanup = pcall(require, "history_cleanup")

    if not ok or not cleanup or not cleanup.run then
        logger.warn("HistoryGuard cleanup is unavailable.")
        return
    end

    local buffering = false

    if rl_buffer and rl_buffer.beginoutput then
        rl_buffer:beginoutput()
        buffering = true
    end

    local success, result = pcall(cleanup.run, {
        quiet = false
    })

    if type(result) == "table" then
        for k,v in pairs(result) do
            print(k,v)
        end
    end

    if not success then
        logger.warn("HistoryGuard cleanup failed: %s", tostring(result))
        return
    end

    if result.aborted then
        logger.notice("")
        logger.notice("HistoryGuard Cleanup")
        logger.notice("==================================================")
        logger.notice("Status : Aborted")
        logger.notice("")
        logger.notice("%s", result.reason)
        logger.notice("==================================================")
        return
    end

    logger.notice("")
    logger.notice("HistoryGuard Cleanup Complete")
    logger.notice("----------------------------------------")
    logger.notice("Removed entries : %d", result.removed)
    logger.notice("Kept entries    : %d", result.kept)

    if result.removed == 0 then
        logger.notice("Your command history is already clean.")
    else
        logger.notice("Removed invalid, duplicate, or rejected history entries.")
    end

end

-- Required because Clink looks for a global function.
_G.historyguard_run_cleanup = commands.cleanup
    
return commands