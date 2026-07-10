--------------------------------------------------------------------------------
-- utils.lua
--
-- Small, dependency-free string helpers shared across HistoryGuard modules.
--------------------------------------------------------------------------------

local utils = {}

function utils.trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

--- Naive whitespace tokenizer that respects simple "..." and '...' quoting.
-- Good enough for typo-detection purposes; it is NOT a full CMD parser
-- (Clink's own line_state APIs already exist for that if ever needed here).
function utils.split_words(line)
    local words = {}
    local i, len = 1, #line
    while i <= len do
        -- skip whitespace
        while i <= len and line:sub(i, i):match("%s") do i = i + 1 end
        if i > len then break end

        local start = i
        local quote = line:sub(i, i)
        if quote == '"' or quote == "'" then
            i = i + 1
            while i <= len and line:sub(i, i) ~= quote do i = i + 1 end
            table.insert(words, line:sub(start + 1, i - 1))
            i = i + 1
        else
            while i <= len and not line:sub(i, i):match("%s") do i = i + 1 end
            table.insert(words, line:sub(start, i - 1))
        end
    end
    return words
end

--- True if the string contains no letters or digits at all (only
-- punctuation/whitespace), e.g. ";;;;", "....", ",,,,".
function utils.is_punctuation_only(s)
    if not s or #s == 0 then return false end
    return s:match("^[^%w]+$") ~= nil
end

--- Heuristic keyboard-smash detector for a single word.
-- Flags things like "asdfasdf", "qqqqqq", "llllllll".
-- This is intentionally conservative: it only flags patterns that are
-- very unlikely to be real command/executable names, since the
-- unknown-executable check is the primary safety net.
function utils.is_keyboard_smash(word)
    if not word or #word < 4 then return false end
    local lower = word:lower()

    -- Case 1: a single character repeated for the whole word ("qqqqqq").
    local first = lower:sub(1, 1)
    if lower:match("^" .. first:gsub("%p", "%%%1") .. "+$") then
        return true
    end

    -- Case 2: only 1-2 distinct characters across a word of length >= 5
    -- (e.g. "ababab", "zxzxzx").
    if #lower >= 5 then
        local distinct = {}
        for c in lower:gmatch(".") do distinct[c] = true end
        local n = 0
        for _ in pairs(distinct) do n = n + 1 end
        if n <= 2 then return true end
    end

    return false
end

--- Splits a comma/space separated PATH-like string into a list.
function utils.split_path(pathstr, sep)
    local list = {}
    if not pathstr then return list end
    for entry in pathstr:gmatch("[^" .. sep .. "]+") do
        table.insert(list, entry)
    end
    return list
end

--- Reads an entire file into a string, or nil if it doesn't exist.
function utils.read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

--- Writes a string to a file, creating parent behavior is caller's job.
function utils.write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

--- Ensures a directory exists (Windows-only, uses mkdir via os.execute).
function utils.ensure_dir(path)
    -- os.execute with 'if not exist' avoids errors when it already exists.
    local cmd = string.format('if not exist "%s" mkdir "%s" >nul 2>nul', path, path)
    os.execute(cmd)
end

return utils
