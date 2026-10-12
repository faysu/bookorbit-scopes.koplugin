-- Ejecuta Sync.run contra el servidor real desde el Mac (solo GET).
-- Uso (desde la carpeta del plugin):
--   luajit tools/probar_servidor.lua <settings.reader.lua> <bookorbit_sync_state.lua> [scope_id ...]
package.path = "./?.lua;" .. package.path
local Sync = require("bscopes_sync")
local settings, state_file = arg[1], arg[2]
local scopes = {}
for i = 3, #arg do scopes[#scopes + 1] = arg[i] end

local function shell_quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function get(path)
    local cmd = "python3 -I tools/bo_get_lua.py " .. shell_quote(settings) .. " " .. shell_quote(path)
    local f = io.popen(cmd)
    local out = f:read("*a"); f:close()
    return assert(loadstring(out))()
end
local function query(path, params)
    local keys = {}
    for k, v in pairs(params or {}) do if v ~= nil and v ~= "" then keys[#keys + 1] = k end end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(params[k]):gsub(" ", "%%20") end
    return #parts > 0 and (path .. "?" .. table.concat(parts, "&")) or path
end

local client = {}
function client:catalogSection(name) return get("/koreader/plugin/catalog/sections/" .. name) end
function client:catalogBooks(params) return get(query("/koreader/plugin/catalog/books", params)) end

-- bookId de los libros del Kindle, del estado del plugin oficial.
local local_ids, seen = {}, {}
for id in io.open(state_file):read("*a"):gmatch('%["bookId"%] = (%d+)') do
    id = tonumber(id)
    if not seen[id] then seen[id] = true; local_ids[#local_ids + 1] = id end
end
table.sort(local_ids)

local t0 = os.time()
local p = Sync.run(client, { local_ids = local_ids, scope_ids = scopes })
print(string.format("libros del Kindle: %d | scopes en el servidor: %d | libros con datos: %s | peticiones: %d | %ds",
    #local_ids, #(p.scopes or {}), p.books and #p.books or "fallo", p.requests, os.time() - t0))
local titles = {}
for _, s in ipairs(p.scopes or {}) do titles[s.id] = s.title end
local by_id = {}
for _, b in ipairs(p.books or {}) do by_id[b.id] = b end
for _, m in ipairs(p.membership) do
    print(string.format("\n[%s] %s -> %d libros (modo %s%s)", m.scope_id, titles[m.scope_id] or "?",
        #m.ids, m.mode, m.partial and ", INCOMPLETA" or ""))
    for _, id in ipairs(m.ids) do
        local b = by_id[id] or {}
        print(string.format("   %4d  %-45s %5s  %s", id, (b.title or "?"):sub(1, 45),
            b.pct and string.format("%.0f%%", b.pct * 100) or "-", b.status or "-"))
    end
end
if #p.errors > 0 then print("\nErrores: " .. table.concat(p.errors, "; ")) end
