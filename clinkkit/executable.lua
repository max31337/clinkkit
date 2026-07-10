--------------------------------------------------------------------------------
-- executable.lua
--
-- Answers "does this executable exist?" cheaply, and can suggest the closest
-- known executable name for a typo. Two layers of caching are used so we
-- NEVER call where.exe more than once per unique word per session:
--   1. In-memory session cache (exists_cache) -- instant repeat lookups.
--   2. A one-time PATH index built with os.globfiles() at load, used both
--      for fast existence checks and as the candidate pool for suggestions.
--
-- Falls back to where.exe only for names not found in the PATH index (e.g.
-- doskey aliases, or PATH changes mid-session), and even then the result
-- is cached.
--------------------------------------------------------------------------------

local levenshtein = require("levenshtein")
local logger = require("logger")

local executable = {}

local exists_cache = {}     -- [lowercase_name] = true/false
local path_index = nil      -- array of lowercase names without extension, built lazily
local path_index_set = nil  -- [lowercase_name] = true, for O(1) lookups

--------------------------------------------------------------------------------
local function get_pathext()
    local raw = os.getenv("PATHEXT") or ".COM;.EXE;.BAT;.CMD"
    local exts = {}
    for ext in raw:gmatch("[^;]+") do
        table.insert(exts, ext:lower())
    end
    return exts
end

local function strip_known_ext(name, exts)
    local lower = name:lower()
    for _, ext in ipairs(exts) do
        if lower:sub(-#ext) == ext then
            return name:sub(1, #name - #ext)
        end
    end
    return name
end

--- Builds the PATH index once. Safe to call multiple times (no-op after first).
function executable.build_path_index()
    if path_index then return end
    path_index = {}
    path_index_set = {}

    local exts = get_pathext()
    local path_env = os.getenv("PATH") or ""

    for dir in path_env:gmatch("[^;]+") do
        -- os.globfiles is a documented Clink/Lua-for-Windows API for
        -- listing files without shelling out. Wrapped in pcall because a
        -- stale/removed PATH entry must never crash Clink.
        local ok, files = pcall(os.globfiles, dir .. "\\*", true)
        if ok and files then
            for _, entry in ipairs(files) do
                local name = type(entry) == "table" and entry.name or entry
                if name then
                    local base = strip_known_ext(name, exts)
                    local lower = base:lower()
                    if not path_index_set[lower] then
                        path_index_set[lower] = true
                        table.insert(path_index, lower)
                    end
                end
            end
        end
    end

    -- Also fold in doskey aliases if the API is available.
    if os.getaliases then
        local ok, aliases = pcall(os.getaliases)
        if ok and aliases then
            for _, a in ipairs(aliases) do 
                local lower = tostring(a):lower()
                if not path_index_set[lower] then
                    path_index_set[lower] = true
                    table.insert(path_index, lower)
                end
            end
        end
    end

    logger.debug("PATH index built: %d executables/aliases", #path_index)
end

--- CMD's own builtins (cd, dir, echo, etc.) should never be flagged as
-- "unknown executable" -- they aren't files on PATH at all.
local CMD_BUILTINS = {
    ["cd"]=true, ["chdir"]=true, ["cls"]=true, ["copy"]=true, ["del"]=true,
    ["dir"]=true, ["echo"]=true, ["exit"]=true, ["for"]=true, ["if"]=true,
    ["md"]=true, ["mkdir"]=true, ["move"]=true, ["popd"]=true, ["pushd"]=true,
    ["rd"]=true, ["ren"]=true, ["rename"]=true, ["rmdir"]=true, ["set"]=true,
    ["start"]=true, ["type"]=true, ["ver"]=true, ["vol"]=true, ["call"]=true,
    ["goto"]=true, ["pause"]=true, ["title"]=true, ["assoc"]=true, ["path"]=true,
    ["prompt"]=true, ["setlocal"]=true, ["endlocal"]=true, ["shift"]=true,
    ["cd.."]=true, ["cd\\"]=true, ["cd-"]=true,
}

--- Returns true/false for whether `name` resolves to something runnable.
function executable.exists(name)
    if not name or name == "" then return false end
    local lower = name:lower()

    if CMD_BUILTINS[lower] then return true end

    if exists_cache[lower] ~= nil then
        return exists_cache[lower]
    end

    -- Directory shortcuts / relative or absolute paths: if it looks like a
    -- path, don't treat it as an "unknown executable" -- that's not what
    -- HistoryGuard is meant to police.
    if name:match("[\\/]") or name:match("^%.%.?$") then
        exists_cache[lower] = true
        return true
    end

    -- Fallback: ask Windows directly via where.exe (cheap, reliable, no PATH index needed).
    local ok, result = pcall(function()
        local pipe = io.popen('where "' .. name:gsub('"', '') .. '" 2>nul')
        if not pipe then return false end
        local out = pipe:read("*a")
        pipe:close()
        return out ~= nil and out:match("%S") ~= nil
    end)

    local found = ok and result or false
    exists_cache[lower] = found
    logger.debug("where.exe lookup for '%s' -> %s", name, tostring(found))
    return found
end

--- Suggests the closest known executable/alias name for a typo'd word.
-- This one DOES need the PATH index, so it builds it on first call.
function executable.suggest(name, max_distance)
    if not path_index then
        executable.build_path_index()
    end
    return levenshtein.closest(name:lower(), path_index, max_distance)
end

return executable
