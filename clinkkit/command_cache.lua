--------------------------------------------------------------------------------
-- command_cache.lua
--
-- Discovers subcommands and flags for known CLI tools (git, go, cargo,
-- dotnet, ...) by invoking their own help output, then caches the results
-- to disk under %LOCALAPPDATA%\clink\historyguard_cache\ so we never pay
-- the discovery cost more than once every `cache_refresh_days`.
--
-- Cache file format is deliberately simple (one token per line, prefixed
-- by "S:" for subcommands or "F:" for flags, "T:" for the unix timestamp
-- of the last refresh) so it can be hand-edited/debugged with Notepad and
-- doesn't require a JSON library.
--------------------------------------------------------------------------------

local logger = require("logger")
local utils = require("utils")

local command_cache = {}

local mem_cache = {}  -- [command] = { subcommands = {...}, flags = {...}, fetched_at = N }

local CACHE_DIR = (os.getenv("LOCALAPPDATA") or os.getenv("TEMP") or ".")
    .. "\\clink\\historyguard_cache"

-- How to discover subcommands/flags for specific tools. Add more here
-- rather than hardcoding tool logic elsewhere in the project.
local DISCOVERY = {
    git    = { cmd = "git help -a 2>&1",       help_cmd = "git --help 2>&1" },
    go     = { cmd = "go help 2>&1",           help_cmd = "go help 2>&1" },
    cargo  = { cmd = "cargo --list 2>&1",       help_cmd = "cargo --help 2>&1" },
    dotnet = { cmd = "dotnet --help 2>&1",      help_cmd = "dotnet --help 2>&1" },
    npm    = { cmd = "npm help -l 2>&1",        help_cmd = "npm --help 2>&1" },
    docker = { cmd = "docker --help 2>&1",      help_cmd = "docker --help 2>&1" },
    kubectl= { cmd = "kubectl --help 2>&1",     help_cmd = "kubectl --help 2>&1" },
    choco  = { cmd = "choco --help 2>&1",       help_cmd = "choco --help 2>&1" },
}

-- Tools whose first non-option argument is a FILE/FOLDER PATH, not a
-- subcommand (editors, pagers, etc.). These must never go through
-- generic --help-based subcommand discovery: free-form help text for
-- these tools routinely word-wraps a description onto its own indented
-- line (e.g. "...compare two files with\n  each"), and extract_subcommands()
-- can mistake that orphan word for a real subcommand. That false entry
-- then makes any real path argument ("code .", "nvim main.go") look like
-- an "unrecognized subcommand" once hg.strict_subcommands is enabled.
--
-- Add tools here, not to DISCOVERY, whenever "tool <path>" is a normal
-- invocation and "tool <path>" is not "tool <subcommand>".
local NO_SUBCOMMANDS = {
    code    = true,
    notepad = true,
    vim     = true,
    nvim    = true,
    subl    = true,
}

--------------------------------------------------------------------------------
local function cache_path(command)
    return CACHE_DIR .. "\\" .. command .. ".cache"
end

local function run_capture(shell_cmd)
    local ok, output = pcall(function()
        local pipe = io.popen(shell_cmd)
        if not pipe then return nil end
        local out = pipe:read("*a")
        pipe:close()
        return out
    end)
    if ok then return output end
    return nil
end

--- Extracts probable subcommand tokens from free-form help text:
-- indented single-word (or dash-word) lines, e.g. "   status    Show ...".
local function extract_subcommands(text)
    local found, seen = {}, {}
    if not text then return found end
    for line in text:gmatch("[^\r\n]+") do
        -- Require a genuine columnar gap (2+ spaces) between the token and
        -- the description that follows -- single-space gaps are far more
        -- likely to be ordinary prose ("Installing and configuring...")
        -- than a real "command    description" help-output row.
        local token = line:match("^%s%s+([%a][%w%-]*)%s%s+%S")
            or line:match("^%s%s+([%a][%w%-]*)%s*$")
        if token and #token >= 2 and #token <= 20 and not seen[token] then
            seen[token] = true
            table.insert(found, token)
        end
    end
    return found
end

--- Extracts probable long/short flags from free-form help text.
local function extract_flags(text)
    local found, seen = {}, {}
    if not text then return found end
    for flag in text:gmatch("%-%-[%a][%w%-]*") do
        if not seen[flag] then
            seen[flag] = true
            table.insert(found, flag)
        end
    end
    return found
end

--------------------------------------------------------------------------------
local function load_from_disk(command)
    local content = utils.read_file(cache_path(command))
    if not content then return nil end

    local entry = { subcommands = {}, flags = {}, fetched_at = 0 }
    for line in content:gmatch("[^\r\n]+") do
        local kind, value = line:match("^(%a):(.*)$")
        if kind == "T" then
            entry.fetched_at = tonumber(value) or 0
        elseif kind == "S" then
            table.insert(entry.subcommands, value)
        elseif kind == "F" then
            table.insert(entry.flags, value)
        end
    end
    return entry
end

local function save_to_disk(command, entry)
    utils.ensure_dir(CACHE_DIR)
    local lines = { "T:" .. tostring(entry.fetched_at) }
    for _, s in ipairs(entry.subcommands) do table.insert(lines, "S:" .. s) end
    for _, f in ipairs(entry.flags) do table.insert(lines, "F:" .. f) end
    utils.write_file(cache_path(command), table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
--- Returns { subcommands = {...}, flags = {...} } for `command`, refreshing
-- from disk/live discovery as needed. Never throws; returns empty lists for
-- unknown tools or on any failure (fail-open, per project error-handling
-- requirements).
function command_cache.get(command, refresh_days)
    command = command:lower()

    if mem_cache[command] then
        return mem_cache[command]
    end

    if NO_SUBCOMMANDS[command] then
        local entry = { subcommands = {}, flags = {}, fetched_at = os.time() }
        mem_cache[command] = entry
        return entry
    end

    local disk = load_from_disk(command)
    local max_age = (refresh_days or 7) * 86400
    local now = os.time()

    if disk and (now - disk.fetched_at) < max_age then
        mem_cache[command] = disk
        return disk
    end

    -- Need a (re)fresh discovery pass.
    local spec = DISCOVERY[command]
    local entry = { subcommands = {}, flags = {}, fetched_at = now }

    if not spec then
        local executable = require("executable")
        if executable.exists(command) then
            spec = { cmd = command .. " --help 2>&1", help_cmd = command .. " --help 2>&1" }
        end
    end

    if spec then
        local ok = pcall(function()
            local sub_text = run_capture(spec.cmd)
            local help_text = run_capture(spec.help_cmd)
            entry.subcommands = extract_subcommands(sub_text or help_text or "")
            entry.flags = extract_flags(help_text or sub_text or "")
        end)
        if not ok then
            logger.warn("discovery failed for '%s'; using empty cache", command)
        else
            logger.info("discovered %d subcommands / %d flags for '%s'",
                #entry.subcommands, #entry.flags, command)
        end
        -- Fallback: some tools (notably git on some Windows installs) may
        -- not produce discoverable help output via the shell environment
        -- used here. Provide a conservative built-in list for git so the
        -- subcommand-typo detector has something to work with immediately.
        if command == "git" and #entry.subcommands == 0 then
            entry.subcommands = {
                "status", "add", "commit", "push", "pull", "checkout",
                "branch", "merge", "rebase", "stash", "log", "diff",
                "reset", "fetch", "clone", "init", "remote", "tag",
                "show", "apply"
            }
            -- flags: a few common ones to allow option-typo detection
            entry.flags = entry.flags or {}
            for _, f in ipairs({"--help", "--version", "--all", "--quiet", "--patch"}) do
                table.insert(entry.flags, f)
            end
            logger.info("using built-in fallback subcommands for 'git' (%d entries)", #entry.subcommands)
        end

        if command == "choco" and #entry.subcommands == 0 then
            entry.subcommands = {
                "install", "uninstall", "upgrade", "list", "search", "info",
                "pin", "source", "config", "feature", "push", "new",
                "outdated", "sync", "apikey", "export", "template",
            }
            logger.info("using built-in fallback subcommands for 'choco' (%d entries)", #entry.subcommands)
        end
        save_to_disk(command, entry)
    elseif disk then
        -- No discovery spec for this tool, but we do have a stale cache;
        -- better than nothing.
        entry = disk
    end

    mem_cache[command] = entry
    return entry
end

--- Forces a re-discovery for one command (used by `historyguard cleanup --refresh`).
function command_cache.refresh(command)
    mem_cache[command] = nil
    local path = cache_path(command)
    os.remove(path)
    return command_cache.get(command, 0)
end

return command_cache