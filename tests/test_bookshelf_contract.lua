-- Valida la fuente contra el registro REAL de Bookshelf
-- (lib/bookshelf_sources.lua del commit fijado en run.sh).
local dir = os.getenv("BOOKSHELF_DIR")
if not dir then
    io.write("  (sin BOOKSHELF_DIR: se omite)\n")
    return
end

package.loaded["logger"] = package.loaded["logger"] or { warn = function() end, info = function() end, dbg = function() end }
local Sources = dofile(dir .. "/lib/bookshelf_sources.lua")
local Source = require("bscopes_source")
local Store = require("bscopes_store")
local Logic = require("bscopes_logic")
local F = require("fixtures")

local function spec()
    local store = Store.new(F.memorySettings())
    store:apply({
        scopes = Logic.normalizeScopes(F.scopes_body),
        books = { Logic.normalizeBook(F.items[703]) },
        local_ids = F.local_ids,
        membership = { { scope_id = "6", ids = { 703 } } },
    }, 1)
    store:markUsed("6")
    return Source.spec{
        store = store,
        available = function() return true end,
        localMaps = function() return { byBookId = F.by_book_id } end,
        exists = function() return true end,
        chooseScope = function() end,
        ensureScopes = function() end,
        requestSync = function() end,
        notify = function() end,
    }
end

T.test("Bookshelf acepta la fuente (API v1)", function()
    T.eq(Sources.API, 1)
    local ok, why = Sources.register(Logic.SOURCE_ID, spec())
    T.eq(ok, true, why)
end)

T.test("aparece en el selector y es de modo list", function()
    local found = false
    for _, id in ipairs(Sources.pickerIds()) do if id == Logic.SOURCE_ID then found = true end end
    T.ok(found)
    T.eq(Sources.isPaged(Logic.SOURCE_ID), false)
    T.eq(Sources.label(Logic.SOURCE_ID), "SmartScope de BookOrbit")
end)

T.test("Bookshelf obtiene los registros y los marca como nuestros", function()
    local recs = Sources.list(Logic.SOURCE_ID, { kind = Logic.SOURCE_ID, scope_id = "6" })
    T.eq(#recs, 1)
    T.eq(recs[1].source_kind, Logic.SOURCE_ID)
    T.eq(recs[1].filepath, F.by_book_id[703])
end)

T.test("los libros son ficheros locales, no remotos", function()
    T.eq(Sources.isRemotePath(F.by_book_id[703]), false)
end)

T.test("si el plugin oficial no está, la fuente desaparece", function()
    local s = spec()
    s.available = function() return false end
    Sources.register(Logic.SOURCE_ID, s)
    T.eq(Sources.isAvailable(Logic.SOURCE_ID), false)
    T.eq(Sources.list(Logic.SOURCE_ID, { scope_id = "6" }), nil)
end)

T.test("Bookshelf acepta la fuente de pila (modo fetch, con carpetas)", function()
    local Stack = require("bscopes_stack")
    local store = Store.new(F.memorySettings())
    store:apply({
        scopes = Logic.normalizeScopes(F.scopes_body),
        books = { Logic.normalizeBook(F.items[703]) },
        local_ids = F.local_ids,
        membership = { { scope_id = "6", ids = { 703, 725 } } },
    }, 1)
    store:markAllUsed()
    local spec = Stack.spec{
        store = store, available = function() return true end,
        localMaps = function() return { byBookId = F.by_book_id } end,
        exists = function() return true end, requestSync = function() end,
        chooseScopeSet = function() end, ensureScopes = function() end, notify = function() end,
    }
    local ok, why = Sources.register(Logic.STACK_SOURCE_ID, spec)
    T.eq(ok, true, why)
    T.eq(Sources.isPaged(Logic.STACK_SOURCE_ID), true)
    local src = { kind = Logic.STACK_SOURCE_ID, mode = "all" }
    local items, total = Sources.fetch(Logic.STACK_SOURCE_ID, src, nil, 0, 8)
    T.eq(total, 1)
    T.eq(items[1].is_folder, true)
    T.eq(items[1].source_nav, true, "Bookshelf la trata como carpeta navegable")
    T.eq(items[1].title, "Fantasía (2)")
    local drill = Sources.drillFor(items[1])
    T.eq(drill.scope_id, "6")
    local books, n = Sources.fetch(Logic.STACK_SOURCE_ID, src, drill, 0, 8)
    T.eq(n, 2)
    T.eq(books[1].source_kind, Logic.STACK_SOURCE_ID)
    T.eq(Sources.isRemotePath(books[1].filepath), false)
    local rows = Sources.editorRows(Logic.STACK_SOURCE_ID, { source = src })
    T.eq(#rows, 1, "botón propio en el editor en lugar de 'Orden del servidor'")
end)
