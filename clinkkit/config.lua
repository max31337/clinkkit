--------------------------------------------------------------------------------
-- config.lua
--
-- Central configuration for HistoryGuard, backed by Clink's settings.add()
-- API so every option is changeable at runtime via:
--     clink set historyguard.<name> <value>
--
-- Whitelist / blacklist are comma-separated strings (settings.add only
-- supports scalar types), parsed into lookup tables on load.
--------------------------------------------------------------------------------

local logger = require("logger")

local config = {}

-- Only register settings once, even if the module is reloaded (Ctrl-X,Ctrl-R).
if not settings.get("hg.enable_cleanup") then

    settings.add("hg.typo_detect", true,
        "HG: reject typos in subcmds/options")

    settings.add("hg.key_smash", true,
        "HG: reject keyboard smashes")

    settings.add("hg.unknown_exe", true,
        "HG: reject unknown commands")

    settings.add("hg.subcmd_detect", true,
        "HG: reject subcommand typos")

    settings.add("hg.strict_subcommands", false,
        "HG: reject any unknown subcommand (may block aliases/extensions)")

    settings.add("hg.option_detect", true,
        "HG: reject flag/option typos")

    settings.add("hg.enable_cleanup", true,
        "HG: allow history cleanup")

    settings.add("hg.max_distance", 2,
        "HG: max edit distance for typos")

    settings.add("hg.whitelist",
        "git,go,cargo,python,py,node,npm,pnpm,yarn,dotnet,code,nvim,vim,rg,fd,docker,kubectl,gh,clink",
        "HG: whitelist of good commands")

    settings.add("hg.blacklist",
        "cls,history,exit,clear",
        "HG: blacklist to exclude")

    settings.add("hg.verbose_logging", "WARN",
        "HG: log level (OFF/WARN/INFO/DEBUG)")

    settings.add("hg.cleanup_on_start", false,
        "HG: cleanup history on startup")

    settings.add("hg.cache_days", 7,
        "HG: days before cache refresh")

    settings.add("hg.show_suggestions", true,
        "HG: show suggestions on rejection")

    settings.add("hg.cleanup_unknown_exe", false,
        "HG: cleanup: check unknown executables (slow, uses where.exe)")

    settings.add("hg.cleanup_option_detect", false,
        "HG: cleanup: check option/flag typos (slow, builds command cache)")

    settings.add("hg.enable_cleanup_keybinding", false,
        "HG: enable Alt-Ctrl-H keybinding for cleanup (requires Clink restart)")
end

--------------------------------------------------------------------------------
local function table_count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function split_csv(s)
    local set = {}
    if not s or s == "" then return set end
    for item in s:gmatch("[^,]+") do
        item = item:match("^%s*(.-)%s*$"):lower()
        if #item > 0 then set[item] = true end
    end
    return set
end

-- Re-read all settings. Called once at load and can be called again if you
-- want to pick up 'clink set' changes without restarting the session.
function config.reload()
    config.enable_typo_detection              = settings.get("hg.typo_detect")
    if config.enable_typo_detection == nil then config.enable_typo_detection = true end

    config.enable_keyboard_smash_detection     = settings.get("hg.key_smash")
    if config.enable_keyboard_smash_detection == nil then config.enable_keyboard_smash_detection = true end

    config.enable_unknown_executable_detection = settings.get("hg.unknown_exe")
    if config.enable_unknown_executable_detection == nil then config.enable_unknown_executable_detection = true end

    config.enable_subcommand_detection         = settings.get("hg.subcmd_detect")
    if config.enable_subcommand_detection == nil then config.enable_subcommand_detection = true end

    config.strict_subcommands                  = settings.get("hg.strict_subcommands")
    if config.strict_subcommands == nil then config.strict_subcommands = false end

    config.enable_option_detection             = settings.get("hg.option_detect")
    if config.enable_option_detection == nil then config.enable_option_detection = true end

    config.enable_cleanup                      = settings.get("hg.enable_cleanup")
    if config.enable_cleanup == nil then config.enable_cleanup = true end

    config.max_distance                        = settings.get("hg.max_distance") or settings.get("historyguard.max_distance") or 2

    config.whitelist                           = split_csv(settings.get("hg.whitelist") or "git,go,cargo,python,py,node,npm,pnpm,yarn,dotnet,code,nvim,vim,rg,fd,docker,kubectl,gh")
    config.blacklist                           = split_csv(settings.get("hg.blacklist") or "cls,history,exit,clear")

    config.verbose_logging                     = settings.get("hg.verbose_logging") or settings.get("historyguard.verbose_logging") or "WARN"

    config.auto_cleanup_on_start               = settings.get("hg.cleanup_on_start")
    if config.auto_cleanup_on_start == nil then config.auto_cleanup_on_start = false end

    config.cache_refresh_days                  = settings.get("hg.cache_days") or 7

    config.show_suggestions                    = settings.get("hg.show_suggestions")
    if config.show_suggestions == nil then config.show_suggestions = settings.get("historyguard.show_suggestions") end
    if config.show_suggestions == nil then config.show_suggestions = true end

    config.cleanup_unknown_exe                 = settings.get("hg.cleanup_unknown_exe")
    if config.cleanup_unknown_exe == nil then config.cleanup_unknown_exe = false end

    config.cleanup_option_detect               = settings.get("hg.cleanup_option_detect")
    if config.cleanup_option_detect == nil then config.cleanup_option_detect = false end

    config.enable_cleanup_keybinding           = settings.get("hg.enable_cleanup_keybinding")
    if config.enable_cleanup_keybinding == nil then config.enable_cleanup_keybinding = false end

    logger.set_level(config.verbose_logging)
    logger.debug("config reloaded (max_distance=%d, whitelist=%d entries, blacklist=%d entries)",
        config.max_distance, table_count(config.whitelist), table_count(config.blacklist))
end

config.reload()

return config
