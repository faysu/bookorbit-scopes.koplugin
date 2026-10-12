local Store = require("bscopes_store")
local F = require("fixtures")

T.test("store vacío", function()
    local s = Store.new(F.memorySettings())
    T.same(s:scopes(), {})
    T.same(s:usedScopes(), {})
    T.eq(s:lastSync(), 0)
    T.eq(s:membership("6"), nil)
end)

T.test("markUsed solo avisa la primera vez y ordena por número", function()
    local s = Store.new(F.memorySettings())
    T.eq(s:markUsed(22), true)
    T.eq(s:markUsed("22"), false)
    T.eq(s:markUsed("6"), true)
    T.same(s:usedScopes(), { "6", "22" })
end)

T.test("apply guarda scopes, libros y pertenencias", function()
    local settings = F.memorySettings()
    local s = Store.new(settings)
    s:apply({
        scopes = { { id = "6", title = "Fantasía" } },
        books = { { id = 703, title = "Las Dos Torres" }, { id = 725, title = "El retorno del rey" } },
        local_ids = { 703, 725 },
        membership = { { scope_id = "6", ids = { 703, 725 }, partial = false, mode = "scan" } },
        errors = {},
    }, 1000)
    T.eq(s:scopeTitle("6"), "Fantasía")
    T.eq(s:books()["703"].title, "Las Dos Torres")
    T.same(s:membership("6").ids, { 703, 725 })
    T.eq(s:membership("6").at, 1000)
    T.eq(s:lastSync(), 1000)
    T.eq(s:lastError(), nil)
    T.ok(settings.flushes > 0)
end)

T.test("apply quita los libros que ya no están en el Kindle", function()
    local s = Store.new(F.memorySettings())
    s:apply({ books = { { id = 1 }, { id = 2 } }, local_ids = { 1, 2 } }, 1)
    s:apply({ books = { { id = 2 } }, local_ids = { 2 } }, 2)
    T.eq(s:books()["1"], nil)
    T.ok(s:books()["2"])
end)

T.test("apply con fallos conserva lo anterior", function()
    local s = Store.new(F.memorySettings())
    s:apply({
        scopes = { { id = "6", title = "Fantasía" } },
        books = { { id = 703, title = "Las Dos Torres" } },
        local_ids = { 703 },
        membership = { { scope_id = "6", ids = { 703 } } },
    }, 1)
    -- Segunda pasada: sin scopes, sin libros (falló) y sin la scope 6.
    s:apply({ membership = {}, errors = { "books: 500", "scope 6: 500" } }, 2)
    T.eq(s:scopeTitle("6"), "Fantasía")
    T.ok(s:books()["703"])
    T.same(s:membership("6").ids, { 703 })
    T.eq(s:lastError(), "books: 500; scope 6: 500")
end)
