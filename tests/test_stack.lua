local Logic = require("bscopes_logic")
local Store = require("bscopes_store")
local Sync = require("bscopes_sync")
local Stack = require("bscopes_stack")
local F = require("fixtures")

local function filledStore(membership)
    local s = Store.new(F.memorySettings())
    local books = {}
    for _, item in pairs(F.items) do books[#books + 1] = Logic.normalizeBook(item) end
    s:apply({
        scopes = Logic.normalizeScopes(F.scopes_body),
        books = books,
        local_ids = F.local_ids,
        membership = membership or {
            { scope_id = "6", ids = { 690, 703, 725 } },
            { scope_id = "21", ids = {} },
            { scope_id = "22", ids = F.local_ids },
        },
    }, 100)
    return s
end

local function deps(store, over)
    local d = { store = store, syncs = {}, notes = {}, covers = {} }
    d.available = function() return true end
    d.localMaps = function() return { byBookId = F.by_book_id } end
    d.exists = function() return true end
    d.cover = function(p) return "bb:" .. p, 10, 15 end
    d.folderCover = function(id, paths) d.covers[id] = paths; return "/cache/scope-" .. id .. ".png" end
    d.requestSync = function(opts) d.syncs[#d.syncs + 1] = opts; if opts.on_done then opts.on_done(true) end end
    d.maybeAutoSync = function() end
    d.notify = function(t) d.notes[#d.notes + 1] = t end
    d.ensureScopes = function(cb) cb(false) end
    d.chooseScopeSet = function(_, _, cb) cb(nil) end
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

T.test("orden de títulos sin tildes ni mayúsculas", function()
    local l = Logic.sortByTitle({ { title = "Zeta" }, { title = "Ángel" }, { title = "avión" }, { title = "¿Quién?" } })
    T.eq(l[1].title, "Ángel"); T.eq(l[2].title, "avión"); T.eq(l[3].title, "¿Quién?"); T.eq(l[4].title, "Zeta")
end)

T.test("carpetas: con 'todas' se ocultan las scopes sin libros en el dispositivo", function()
    local s = filledStore()
    local e = Logic.scopeFolders(s:scopes(), nil, function(id) return s:membership(id) end, F.by_book_id)
    local names = {}
    for i, x in ipairs(e) do names[i] = x.title .. "=" .. x.count end
    -- Arte (18) no está sincronizada y Leídos (21) tiene 0: fuera.
    T.same(names, { "Fantasía=3", "Leyendo o queriendo leer=6" })
end)

T.test("carpetas: las elegidas a mano salen aunque tengan 0", function()
    local s = filledStore()
    local e = Logic.scopeFolders(s:scopes(), { "21", "6" }, function(id) return s:membership(id) end, F.by_book_id)
    T.eq(#e, 2)
    T.eq(e[1].title, "Fantasía"); T.eq(e[2].title, "Leídos"); T.eq(e[2].count, 0)
end)

T.test("registro de carpeta: número en el título y entrada para abrirla", function()
    local r = Logic.folderRecord({ scope_id = "6", title = "Fantasía", count = 3 }, "%1 (%2)", "/c/6.png")
    T.eq(r.is_folder, true); T.eq(r.title, "Fantasía (3)"); T.eq(r.cover_image_path, "/c/6.png")
    T.same(r.drill, { label = "Fantasía", scope_id = "6" })
    T.eq(Logic.folderRecord({ scope_id = "1", title = "100% ciencia", count = 2 }).title, "100% ciencia (2)")
end)

T.test("store: 'todas' añade todas las scopes de la lista a las que se sincronizan", function()
    local s = filledStore()
    T.eq(s:usesAll(), false)
    T.eq(s:markAllUsed(), true)
    T.eq(s:markAllUsed(), false)
    T.same(s:usedScopes(), { "6", "18", "21", "22" })
end)

T.test("sync con all_scopes comprueba todas las scopes recién descargadas", function()
    local server = F.fakeServer({ honor_ids_with_scope = false })
    local client = {}
    function client:catalogSection() return F.scopes_body end
    function client:catalogBooks(p) return server.books(p) end
    local p = Sync.run(client, { local_ids = F.local_ids, scope_ids = { "6" }, all_scopes = true })
    local ids = {}
    for i, m in ipairs(p.membership) do ids[i] = m.scope_id end
    T.same(ids, { "6", "18", "21", "22" })
end)

T.test("fetch sin abrir: carpetas ordenadas, con portada y total", function()
    local s = filledStore()
    s:markAllUsed()
    local d = deps(s)
    local items, total = Stack.spec(d).fetch({ kind = Logic.STACK_SOURCE_ID, mode = "all" }, nil, 0, 10)
    T.eq(total, 2)
    T.eq(items[1].title, "Fantasía (3)")
    T.eq(items[1].cover_image_path, "/cache/scope-6.png")
    T.eq(#d.covers["6"], 3, "la portada sale de los libros de esa scope")
    T.eq(items[2].title, "Leyendo o queriendo leer (6)")
    T.eq(#d.syncs, 0)
end)

T.test("fetch dentro de una carpeta: sus libros, por título, con portada y progreso", function()
    local s = filledStore()
    s:markAllUsed()
    local spec = Stack.spec(deps(s))
    local folder = spec.fetch({ mode = "all" }, nil, 0, 10)[1]
    local drill = spec.open_folder(folder)
    local books, total = spec.fetch({ mode = "all" }, drill, 0, 2)
    T.eq(total, 3)
    T.eq(#books, 2, "solo la página pedida")
    T.eq(books[1].title, "El retorno del rey")
    T.eq(books[1].cover_bb, "bb:" .. F.by_book_id[725])
    T.eq(books[2].title, "Festín de cuervos + Danza de dragones")
    local rest = spec.fetch({ mode = "all" }, drill, 2, 2)
    T.eq(rest[1].title, "Las Dos Torres")
    T.near(rest[1].book_pct, 0.7183)
end)

T.test("primera vez con 'todas': pide sincronizar", function()
    local s = filledStore()
    local d = deps(s)
    Stack.spec(d).fetch({ mode = "all" }, nil, 0, 10)
    T.eq(#d.syncs, 1)
    T.eq(s:usesAll(), true)
end)

T.test("elegir 'todas' y poner nombre", function()
    local s = filledStore()
    local d = deps(s, {
        chooseScopeSet = function(_, _, cb) cb({ mode = "all" }) end,
        askName = function(p, cb) T.eq(p, "SmartScopes de BookOrbit"); cb("Categorías") end,
    })
    local draft = { label = "Nueva estantería", source = { kind = Logic.STACK_SOURCE_ID } }
    local res = "pendiente"
    Stack.spec(d).pick(draft, function(v) res = v end)
    T.eq(res, nil)
    T.eq(draft.source.mode, "all"); T.eq(draft.label, "Categorías")
    T.eq(s:usesAll(), true)
end)

T.test("elegir a mano: guarda las scopes marcadas", function()
    local s = filledStore()
    local d = deps(s, { chooseScopeSet = function(_, _, cb) cb({ mode = "selected", scope_ids = { "6", "21" } }) end })
    local draft = { source = {} }
    Stack.spec(d).pick(draft, function() end)
    T.eq(draft.source.mode, "selected")
    T.same(draft.source.scope_ids, { "6", "21" })
    T.same(s:usedScopes(), { "6", "21" })
    local items = Stack.spec(d).fetch(draft.source, nil, 0, 10)
    T.eq(#items, 2); T.eq(items[2].title, "Leídos (0)")
end)

T.test("cancelar al elegir deja la estantería como estaba", function()
    local draft = { source = { mode = "all" } }
    local res
    Stack.spec(deps(filledStore())).pick(draft, function(v) res = v end)
    T.eq(res, false); T.eq(draft.source.mode, "all")
end)

T.test("un nombre propio no se pisa", function()
    local proposed
    local d = deps(filledStore(), {
        chooseScopeSet = function(_, _, cb) cb({ mode = "all" }) end,
        askName = function(p, cb) proposed = p; cb(nil) end,
    })
    local draft = { label = "Mis categorías", source = {} }
    Stack.spec(d).pick(draft, function() end)
    T.eq(proposed, "Mis categorías"); T.eq(draft.label, "Mis categorías")
end)

T.test("editor: botón con el resumen que cambia la selección", function()
    local d = deps(filledStore(), { chooseScopeSet = function(_, _, cb) cb({ mode = "selected", scope_ids = { "22" } }) end })
    local rows = Stack.spec(d).editor_rows({ source = { mode = "all" } })
    local btn = rows[1][1]
    local draft = { source = { mode = "all" } }
    T.eq(btn.text(draft), "SmartScopes: todas")
    local redrawn = false
    btn.callback(draft, function() redrawn = true end)
    T.ok(redrawn)
    T.eq(btn.text(draft), "SmartScopes: 1 elegidas")
end)
