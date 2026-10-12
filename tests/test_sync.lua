local Sync = require("bscopes_sync")
local F = require("fixtures")

local function fakeClient(server, opts)
    opts = opts or {}
    local c = { section_calls = 0 }
    function c:catalogSection(name)
        self.section_calls = self.section_calls + 1
        if opts.section_err then return nil, opts.section_err end
        T.eq(name, "smart-scopes")
        return F.scopes_body
    end
    function c:catalogBooks(params) return server.books(params) end
    return c
end

T.test("sync completo con BookOrbit 3.3.0", function()
    local server = F.fakeServer({ honor_ids_with_scope = false })
    local p = Sync.run(fakeClient(server), { local_ids = F.local_ids, scope_ids = { "6", "22" } })
    T.eq(#p.scopes, 4)
    T.eq(#p.books, 6)
    T.eq(#p.membership, 2)
    T.same(p.membership[1].ids, { 690, 703, 725 })
    T.same(p.membership[2].ids, F.local_ids)
    T.same(p.errors, {})
    -- 1 lista de scopes + 1 bloque de libros + 1 página por scope (todas caben en 100).
    T.eq(p.requests, 4)
end)

T.test("los libros se piden sin smartScopeId (ahí sí se aplica ids)", function()
    local server = F.fakeServer()
    Sync.run(fakeClient(server), { local_ids = F.local_ids, scope_ids = {} })
    T.eq(#server.calls, 1)
    T.eq(server.calls[1].smartScopeId, nil)
    T.eq(server.calls[1].ids, "668,679,690,703,718,725")
end)

T.test("credenciales rechazadas: no sigue pidiendo", function()
    local server = F.fakeServer()
    local p = Sync.run(fakeClient(server, { section_err = 401 }), { local_ids = F.local_ids, scope_ids = { "6" } })
    T.eq(#server.calls, 0)
    T.eq(p.books, nil)
    T.eq(#p.errors, 1)
end)

T.test("fallo en los libros: no se mandan (se conserva la caché)", function()
    local server = F.fakeServer({ fail_on_call = 1 })
    local p = Sync.run(fakeClient(server), { local_ids = F.local_ids, scope_ids = { "22" } })
    T.eq(p.books, nil)
    T.eq(#p.membership, 1)
    T.eq(#p.errors, 1)
end)

T.test("solo listas y claves de texto (sobrevive al subproceso)", function()
    local server = F.fakeServer()
    local p = Sync.run(fakeClient(server), { local_ids = F.local_ids, scope_ids = { "6" } })
    local function check(t, path)
        local n = #t
        for k, v in pairs(t) do
            if type(k) == "number" then
                T.ok(k >= 1 and k <= n and k % 1 == 0, "clave numérica dispersa en " .. path)
            else
                T.eq(type(k), "string", path)
            end
            if type(v) == "table" then check(v, path .. "." .. tostring(k)) end
        end
    end
    check(p, "payload")
end)
