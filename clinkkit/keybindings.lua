--------------------------------------------------------------------------------
-- keybindings.lua
--
-- Handles all HistoryGuard keyboard shortcut registration.
--
-- Responsibilities:
--
--   • Register Clink keybindings
--   • Ensure .inputrc contains required bindings
--
-- Does NOT perform cleanup itself.
--------------------------------------------------------------------------------

local config = require("config")
local logger = require("logger")

local keybindings = {}

--------------------------------------------------------------------------------
-- Resolve active Clink profile
--------------------------------------------------------------------------------

local function get_profile_dir()

    local profile = os.getenv("CLINK_PROFILE")

    if profile and profile ~= "" then
        return profile
    end

    local localappdata = os.getenv("LOCALAPPDATA")

    if not localappdata then
        return nil
    end

    return localappdata .. "\\clink"

end

--------------------------------------------------------------------------------
-- Ensure profile directory exists
--------------------------------------------------------------------------------

local function ensure_profile_dir(path)

    local ok, exists = pcall(os.isdir, path)

    if ok and exists then
        return true
    end

    local mk_ok = pcall(os.mkdir, path)

    return mk_ok

end

--------------------------------------------------------------------------------
-- Ensure .inputrc contains cleanup binding
--------------------------------------------------------------------------------

local function ensure_inputrc_keybinding()

    if not config.enable_cleanup_keybinding then
        return
    end

    local profile = get_profile_dir()

    if not profile then
        logger.warn("Unable to determine Clink profile directory.")
        return
    end

    if not ensure_profile_dir(profile) then
        logger.warn("Unable to create Clink profile directory.")
        return
    end

    local inputrc = profile .. "\\.inputrc"

    local binding =
        'M-C-h: "luafunc:historyguard_run_cleanup"'

    local content = ""

    local file = io.open(inputrc, "r")

    if file then
        content = file:read("*a")
        file:close()
    end

    if content:find("historyguard_run_cleanup", 1, true) then
        logger.debug(".inputrc already contains cleanup binding.")
        return
    end

    if content ~= "" and not content:match("\n$") then
        content = content .. "\n"
    end

    content = content .. binding .. "\n"

    local out = io.open(inputrc, "w")

    if not out then
        logger.warn("Unable to write %s", inputrc)
        return
    end

    out:write(content)
    out:close()

    logger.notice("Installed HistoryGuard cleanup keybinding into .inputrc")

end

--------------------------------------------------------------------------------
-- Register runtime Clink bindings
--------------------------------------------------------------------------------

local function register_clink_bindings()

    if not config.enable_cleanup_keybinding then
        return
    end

    local ok, err = pcall(function()

        clink.bind(
            "M-C-h",
            "luafunc:historyguard_run_cleanup"
        )

    end)

    if ok then
        logger.debug("Registered runtime cleanup keybinding.")
    else
        logger.warn("Failed to register cleanup keybinding: %s", tostring(err))
    end

end

--------------------------------------------------------------------------------
-- Public initializer
--------------------------------------------------------------------------------

function keybindings.initialize()

    register_clink_bindings()

    ensure_inputrc_keybinding()

end

return keybindings