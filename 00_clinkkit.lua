-- Loader: add the bundled `clinkkit/` directory to `package.path`
-- so Clink (which only loads top-level scripts) can `require()` the
-- module files living in the `clinkkit` subfolder.
local localapp = os.getenv("LOCALAPPDATA")
if not localapp then return end
local kit_path = localapp .. "\\clink\\clinkkit\\?.lua"
package.path = kit_path .. ";" .. package.path

local ok, err = pcall(require, "history_guard")
if not ok and clink and clink.debugprint then
    clink.debugprint("[clinkkit] failed to load: " .. tostring(err))
end
