-- Mini corredor de tests (sin dependencias). Se lanza desde tests/run.sh.
package.path = "./?.lua;./tests/?.lua;" .. package.path

local T = { passed = 0, failed = 0, current = "" }
_G.T = T

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "esperado " .. fmt(expected) .. ", obtenido " .. fmt(actual), 2)
    end
end

function T.ok(cond, msg)
    if not cond then error(msg or "condición falsa", 2) end
end

function T.near(actual, expected, eps, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-9) then
        error((msg and (msg .. ": ") or "") .. "esperado ~" .. fmt(expected) .. ", obtenido " .. fmt(actual), 2)
    end
end

function T.same(a, b, msg)
    local function ser(x)
        if type(x) ~= "table" then return fmt(x) end
        local keys = {}
        for k in pairs(x) do keys[#keys + 1] = k end
        table.sort(keys, function(p, q) return tostring(p) < tostring(q) end)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(x[k]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    local sa, sb = ser(a), ser(b)
    if sa ~= sb then error((msg and (msg .. ": ") or "") .. "esperado " .. sb .. ", obtenido " .. sa, 2) end
end

function T.test(name, fn)
    T.current = name
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
        io.write("  ok   ", name, "\n")
    else
        T.failed = T.failed + 1
        io.write("  FALLO ", name, "\n", "       ", tostring(err):gsub("\n", "\n       "), "\n")
    end
end

-- Idioma fijo para que los tests no dependan del LANG del equipo.
require("bscopes_i18n").setLanguage("es")

local suites = { "test_logic", "test_store", "test_sync", "test_source", "test_stack", "test_bookshelf_contract", "test_service", "test_i18n" }
local only = arg and arg[1]
for _, name in ipairs(suites) do
    if not only or only == name then
        io.write(name, "\n")
        dofile("tests/" .. name .. ".lua")
    end
end
io.write(string.format("\n%d correctos, %d fallidos\n", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
