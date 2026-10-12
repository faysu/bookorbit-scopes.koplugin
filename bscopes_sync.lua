-- bscopes_sync.lua -- una pasada de sincronización con BookOrbit.
--
-- Se ejecuta dentro del subproceso del cliente del plugin oficial
-- (BookOrbitApi:runInSubprocess), así que cada petición es bloqueante y la
-- pantalla no se congela. Solo hace GET: no escribe nada en el servidor ni en
-- los sidecars.
--
-- Lo que devuelve viaja serializado al proceso principal: solo listas y
-- tablas con claves de texto.

local Logic = require("bscopes_logic")

local Sync = {}

-- client: BookOrbitApi (catalogSection, catalogBooks).
-- opts.local_ids: bookId de los libros del Kindle.
-- opts.scope_ids: scopes a comprobar (las que usan las estanterías).
-- opts.with_scopes: pedir también la lista de SmartScopes.
function Sync.run(client, opts)
    opts = opts or {}
    local local_ids = opts.local_ids or {}
    local payload = { errors = {}, membership = {}, local_ids = local_ids, requests = 0 }

    local function fetch(params)
        payload.requests = payload.requests + 1
        return client:catalogBooks(params)
    end

    if opts.with_scopes ~= false then
        payload.requests = payload.requests + 1
        local body, err = client:catalogSection("smart-scopes")
        if type(body) == "table" then
            payload.scopes = Logic.normalizeScopes(body)
        else
            payload.errors[#payload.errors + 1] = "smart-scopes: " .. tostring(err)
            if err == 401 or err == 403 then return payload end
        end
    end

    -- Datos y progreso en el servidor de los libros del Kindle. Sin
    -- smartScopeId el filtro ids sí se aplica.
    local books, books_ok = {}, true
    for _, chunk in ipairs(Logic.chunk(local_ids, Logic.PAGE_SIZE)) do
        local body, err = fetch({ ids = table.concat(chunk, ","), size = Logic.PAGE_SIZE, page = 1, sort = "title" })
        if type(body) ~= "table" then
            books_ok = false
            payload.errors[#payload.errors + 1] = "books: " .. tostring(err)
            break
        end
        for _, item in ipairs(type(body.items) == "table" and body.items or {}) do
            local b = Logic.normalizeBook(item)
            if b then books[#books + 1] = b end
        end
    end
    if books_ok then payload.books = books end

    for _, scope_id in ipairs(opts.scope_ids or {}) do
        local ids, info = Logic.collectScopeMembers(fetch, scope_id, local_ids, opts)
        if ids then
            payload.membership[#payload.membership + 1] = {
                scope_id = tostring(scope_id),
                ids = ids,
                partial = info.partial,
                mode = info.mode,
            }
        else
            payload.errors[#payload.errors + 1] = "scope " .. tostring(scope_id) .. ": " .. tostring(info)
        end
    end
    return payload
end

return Sync
