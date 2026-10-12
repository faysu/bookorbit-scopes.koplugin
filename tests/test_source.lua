local Source = require("bscopes_source")
local Store = require("bscopes_store")
local Logic = require("bscopes_logic")
local F = require("fixtures")

local function filledStore()
    local s = Store.new(F.memorySettings())
    local books = {}
    for _, item in pairs(F.items) do books[#books + 1] = Logic.normalizeBook(item) end
    s:apply({
        scopes = Logic.normalizeScopes(F.scopes_body),
        books = books,
        local_ids = F.local_ids,
        membership = { { scope_id = "6", ids = { 690, 703, 725 } } },
    }, 100)
    return s
end

local function deps(store, over)
    local d = {
        store = store,
        syncs = {},
        notes = {},
        available = function() return true end,
        localMaps = function() return { byBookId = F.by_book_id } end,
        localProgress = function() return nil end,
        exists = function() return true end,
        chooseScope = function(_, cb) cb(nil) end,
        ensureScopes = function(cb) cb(false) end,
        maybeAutoSync = function() end,
    }
    d.requestSync = function(opts) d.syncs[#d.syncs + 1] = opts; if opts.on_done then opts.on_done(true) end end
    d.notify = function(t) d.notes[#d.notes + 1] = t end
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

T.test("list: solo libros del Kindle que están en la scope, sin red", function()
    local store = filledStore()
    store:markUsed("6")
    local d = deps(store)
    local spec = Source.spec(d)
    local recs = spec.list({ kind = Logic.SOURCE_ID, scope_id = "6" })
    local titles = {}
    for i, r in ipairs(recs) do titles[i] = r.title end
    table.sort(titles)
    T.same(titles, { "El retorno del rey", "Festín de cuervos + Danza de dragones", "Las Dos Torres" })
    T.eq(#d.syncs, 0, "scope ya conocida: no lanza sincronización")
end)

T.test("list: estantería con scope aún no sincronizada -> vacía y pide sync", function()
    local d = deps(filledStore())
    local recs = Source.spec(d).list({ kind = Logic.SOURCE_ID, scope_id = "22" })
    T.same(recs, {})
    T.eq(#d.syncs, 1)
    T.eq(d.syncs[1].reason, "new_scope")
end)

T.test("list: sin scope elegida -> vacía", function()
    T.same(Source.spec(deps(filledStore())).list({ kind = Logic.SOURCE_ID }), {})
end)

T.test("list: el progreso del Kindle gana si es mayor", function()
    local store = filledStore()
    store:markUsed("6")
    local recs = Source.spec(deps(store, {
        localProgress = function(p) if p:find("retorno") then return 0.9, "reading" end end,
    })).list({ scope_id = "6" })
    for _, r in ipairs(recs) do
        if r.bookorbit_id == 725 then T.near(r.book_pct, 0.9) end
        if r.bookorbit_id == 703 then T.near(r.book_pct, 0.7183) end
    end
end)

T.test("pick: guarda la scope en la estantería y la nombra", function()
    local store = filledStore()
    local d = deps(store, {
        chooseScope = function(scopes, cb)
            T.eq(#scopes, 4)
            cb(scopes[2])
        end,
    })
    local draft = { source = { kind = Logic.SOURCE_ID } }
    local result = "pendiente"
    Source.spec(d).pick(draft, function(v) result = v end)
    T.eq(result, nil, "done() sin argumentos = aceptado")
    T.eq(draft.source.scope_id, "6")
    T.eq(draft.source.scope_title, "Fantasía")
    T.eq(draft.label, "Fantasía")
    T.same(store:usedScopes(), { "6" })
    T.eq(d.syncs[1].reason, "picked")
end)

T.test("pick: cancelar deja la estantería como estaba", function()
    local draft = { source = { kind = Logic.SOURCE_ID } }
    local result
    Source.spec(deps(filledStore())).pick(draft, function(v) result = v end)
    T.eq(result, false)
    T.eq(draft.source.scope_id, nil)
end)

T.test("pick sin lista guardada y sin red -> aviso y cancelación", function()
    local d = deps(Store.new(F.memorySettings()))
    local result
    Source.spec(d).pick({ source = {} }, function(v) result = v end)
    T.eq(result, false)
    T.eq(#d.notes, 1)
end)

T.test("pick sin lista guardada: la descarga y luego deja elegir", function()
    local store = Store.new(F.memorySettings())
    local d = deps(store, {
        ensureScopes = function(cb)
            store:apply({ scopes = Logic.normalizeScopes(F.scopes_body) }, 1)
            cb(true)
        end,
        chooseScope = function(scopes, cb) cb(scopes[4]) end,
    })
    local draft = { source = {} }
    Source.spec(d).pick(draft, function() end)
    T.eq(draft.source.scope_id, "22")
end)

T.test("refresh: fuerza la sincronización y llama a done", function()
    local d = deps(filledStore())
    local called = false
    Source.spec(d).refresh({ scope_id = "6" }, nil, function() called = true end)
    T.ok(called)
    T.eq(d.syncs[1].force, true)
end)

T.test("cover: delega en la caché de portadas con la ruta", function()
    local got
    local spec = Source.spec(deps(filledStore(), { cover = function(p) got = p; return "bb", 10, 20 end }))
    local bb, w, h = spec.cover({ filepath = "/mnt/us/x.epub" })
    T.eq(got, "/mnt/us/x.epub"); T.eq(bb, "bb"); T.eq(w, 10); T.eq(h, 20)
end)
