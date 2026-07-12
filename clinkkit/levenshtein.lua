--------------------------------------------------------------------------------
-- levenshtein.lua
--
-- Pure-Lua edit distance, implemented from scratch.
--
-- Uses Optimal String Alignment (OSA) distance -- standard Levenshtein
-- (insert/delete/substitute) PLUS adjacent-transposition as a single edit
-- (e.g. "stauts" -> "status" costs 1, not 2). This matches how humans
-- actually mistype commands (fat-fingering two adjacent keys is extremely
-- common and should be treated as one typo, not two).
--
-- OSA is "restricted" Damerau-Levenshtein: each substring may be edited
-- at most once (no reusing a transposed pair), which is simpler and cheaper
-- than true Damerau-Levenshtein and is the standard choice for typo
-- correction (same approach used by things like git's "did you mean").
--
-- Case-insensitive by default since command typos rarely differ by case.
--------------------------------------------------------------------------------

local levenshtein = {}

--- Computes the OSA edit distance between strings a and b.
-- @param a string
-- @param b string
-- @param case_sensitive boolean (optional, default false)
-- @param allow_transposition boolean (optional, default true)
-- @return integer distance
function levenshtein.distance(a, b, case_sensitive, allow_transposition)
    a = a or ""
    b = b or ""
    if not case_sensitive then
        a = a:lower()
        b = b:lower()
    end
    if allow_transposition == nil then
        allow_transposition = true
    end

    local len_a, len_b = #a, #b
    if len_a == 0 then return len_b end
    if len_b == 0 then return len_a end
    if a == b then return 0 end

    -- Full (len_a+1) x (len_b+1) DP table. Command/subcommand/flag strings
    -- are short (a handful of chars), so the O(n*m) memory cost here is
    -- negligible -- and a full table is what makes the transposition rule
    -- easy to get right (it needs to look back to row i-2, col j-2).
    local d = {}
    for i = 0, len_a do
        d[i] = {}
        d[i][0] = i
    end
    for j = 0, len_b do
        d[0][j] = j
    end

    for i = 1, len_a do
        local char_a = a:sub(i, i)
        for j = 1, len_b do
            local char_b = b:sub(j, j)
            local cost = (char_a == char_b) and 0 or 1

            local deletion     = d[i - 1][j] + 1
            local insertion    = d[i][j - 1] + 1
            local substitution = d[i - 1][j - 1] + cost

            local min_val = deletion
            if insertion < min_val then min_val = insertion end
            if substitution < min_val then min_val = substitution end

            if allow_transposition and i > 1 and j > 1
                and char_a == b:sub(j - 1, j - 1)
                and a:sub(i - 1, i - 1) == char_b then
                local transposition = d[i - 2][j - 2] + 1
                if transposition < min_val then min_val = transposition end
            end

            d[i][j] = min_val
        end
    end

    return d[len_a][len_b]
end

--- Finds the closest match to `word` among `candidates` (an array of
-- strings) within max_distance. Returns best_match, best_distance, or
-- nil if nothing is within range.
--
-- Exact-match guard: if `word` already equals one of the candidates
-- (case-insensitively), this returns nil immediately -- a word that is
-- already valid must never be "corrected" into something else, even if
-- another candidate happens to sit within max_distance of it.
function levenshtein.closest(word, candidates, max_distance, allow_transposition)
    if not word or word == "" then return nil end
    local word_lower = word:lower()

    for _, candidate in ipairs(candidates) do
        if candidate:lower() == word_lower then
            return nil
        end
    end

    local best_word, best_dist = nil, (max_distance or 2) + 1

    for _, candidate in ipairs(candidates) do
        if candidate:lower() ~= word_lower then
            -- Cheap pre-filter: skip candidates whose length differs too much
            -- to possibly be within max_distance. Avoids wasted DP work.
            if math.abs(#candidate - #word) <= best_dist then
                local d = levenshtein.distance(word, candidate, false, allow_transposition)
                if d < best_dist then
                    best_dist = d
                    best_word = candidate
                end
            end
        end
    end

    if best_word and best_dist <= (max_distance or 2) then
        return best_word, best_dist
    end
    return nil
end

return levenshtein