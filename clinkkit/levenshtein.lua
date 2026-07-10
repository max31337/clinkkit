--------------------------------------------------------------------------------
-- levenshtein.lua
--
-- Pure-Lua Levenshtein (edit) distance, implemented from scratch with a
-- rolling two-row dynamic-programming table (O(n) memory, O(n*m) time).
-- Case-insensitive by default since command typos rarely differ by case.
--------------------------------------------------------------------------------

local levenshtein = {}

--- Computes the edit distance between strings a and b.
-- @param a string
-- @param b string
-- @param case_sensitive boolean (optional, default false)
-- @return integer distance
function levenshtein.distance(a, b, case_sensitive)
    a = a or ""
    b = b or ""
    if not case_sensitive then
        a = a:lower()
        b = b:lower()
    end

    local len_a, len_b = #a, #b
    if len_a == 0 then return len_b end
    if len_b == 0 then return len_a end
    if a == b then return 0 end

    -- Quick reject: if the length gap alone exceeds any sane threshold,
    -- callers can short circuit before calling this, but we still compute
    -- correctly here.
    local prev_row = {}
    local curr_row = {}

    for j = 0, len_b do
        prev_row[j] = j
    end

    for i = 1, len_a do
        curr_row[0] = i
        local char_a = a:sub(i, i)
        for j = 1, len_b do
            local cost = (char_a == b:sub(j, j)) and 0 or 1
            local deletion     = prev_row[j] + 1
            local insertion    = curr_row[j - 1] + 1
            local substitution = prev_row[j - 1] + cost
            local min_val = deletion
            if insertion < min_val then min_val = insertion end
            if substitution < min_val then min_val = substitution end
            curr_row[j] = min_val
        end
        prev_row, curr_row = curr_row, prev_row
    end

    return prev_row[len_b]
end

--- Finds the closest match to `word` among `candidates` (an array of
-- strings) within max_distance. Returns best_match, best_distance, or
-- nil if nothing is within range.
function levenshtein.closest(word, candidates, max_distance)
    if not word or word == "" then return nil end
    local best_word, best_dist = nil, (max_distance or 2) + 1

    for _, candidate in ipairs(candidates) do
        if candidate ~= word then
            -- Cheap pre-filter: skip candidates whose length differs too much
            -- to possibly be within max_distance. Avoids wasted DP work.
            if math.abs(#candidate - #word) <= best_dist then
                local d = levenshtein.distance(word, candidate)
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
