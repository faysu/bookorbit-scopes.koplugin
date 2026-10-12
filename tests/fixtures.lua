-- Datos sacados de respuestas reales de BookOrbit 3.3.0 (12/10/2026) y del
-- estado del plugin oficial en el Kindle. Recortados a lo que usa el plugin.
local F = {}

-- GET /koreader/plugin/catalog/sections/smart-scopes (extracto)
F.scopes_body = {
    section = "smart-scopes",
    items = {
        { id = "18", title = "Arte, cine y ensayo literario", section = "smart-scopes", icon = "Palette" },
        { id = "6", title = "Fantasía", section = "smart-scopes", icon = "Sparkles" },
        { id = "21", title = "Leídos", section = "smart-scopes", icon = "BookCheck" },
        { id = "22", title = "Leyendo o queriendo leer", section = "smart-scopes", icon = "Binoculars" },
    },
}

-- Elementos de GET /koreader/plugin/catalog/books
F.items = {
    [668] = { id = 668, title = "Africanus. El hijo del cónsul", authors = { "Santiago Posteguillo" },
        seriesId = 821, seriesName = "Publio Cornelio Escipión", seriesIndex = "1",
        progressPercentage = 4.78, lastReadAt = "2025-10-06T22:00:15.000Z", readStatus = "reading",
        formats = { "epub" }, addedAt = "2026-10-07T21:24:33.057Z" },
    [679] = { id = 679, title = "El guardián entre el centeno", authors = { "J. D. Salinger" },
        progressPercentage = nil, lastReadAt = nil, readStatus = "want_to_read", formats = { "epub" } },
    [690] = { id = 690, title = "Festín de cuervos + Danza de dragones", authors = { "George R. R. Martin" },
        seriesName = "Canción de hielo y fuego", seriesIndex = "4.5", readStatus = "want_to_read" },
    [703] = { id = 703, title = "Las Dos Torres", authors = { "J. R. R. Tolkien" },
        seriesName = "El Señor de los Anillos", seriesIndex = "2",
        progressPercentage = 71.83, lastReadAt = "2026-10-07T22:38:44.930Z", readStatus = "reading" },
    [718] = { id = 718, title = "Steve Jobs", authors = { "Walter Isaacson" }, readStatus = "rereading" },
    [725] = { id = 725, title = "El retorno del rey", authors = { "J. R. R. Tolkien" },
        progressPercentage = 1, lastReadAt = "2026-08-05T00:41:37.000Z", readStatus = "reading" },
}

-- Libros del Kindle (bookId -> ruta), como StateManager.onDeviceMaps().byBookId
F.by_book_id = {
    [668] = "/mnt/us/documents/Libros/Africanus. El hijo del cónsul.epub",
    [679] = "/mnt/us/documents/Libros/El guardián entre el centeno.epub",
    [690] = "/mnt/us/documents/Libros/Festín de cuervos + Danza de dragones.epub",
    [703] = "/mnt/us/documents/Libros/Las Dos Torres.epub",
    [718] = "/mnt/us/documents/Libros/Steve Jobs.epub",
    [725] = "/mnt/us/documents/Libros/El retorno del rey.epub",
}

F.local_ids = { 668, 679, 690, 703, 718, 725 }

-- Pertenencia real (en el servidor) de cada scope: incluye libros que NO
-- están en el Kindle, como pasa en la realidad.
F.scope_members = {
    ["6"] = { 690, 703, 725, 1035, 1046, 1074, 1077, 1090 },  -- Fantasía
    ["21"] = { 680, 681, 695 },                                -- Leídos (ninguno en el Kindle)
    ["22"] = { 668, 679, 690, 703, 718, 725 },                 -- Leyendo o queriendo leer
}

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end

-- Servidor falso de /catalog/books.
-- honor_ids_with_scope = false reproduce BookOrbit 3.3.0 (ignora ids con
-- smartScopeId); true, el comportamiento deseable.
function F.fakeServer(opts)
    opts = opts or {}
    local server = { calls = {} }
    local function itemFor(id)
        return F.items[id] and copy(F.items[id]) or { id = id, title = "Libro " .. id, authors = {} }
    end
    function server.books(params)
        server.calls[#server.calls + 1] = copy(params)
        if opts.fail_on_call and #server.calls == opts.fail_on_call then return nil, 500 end
        local ids
        if params.ids then
            ids = {}
            for s in tostring(params.ids):gmatch("[^,]+") do ids[tonumber(s)] = true end
        end
        local pool = {}
        if params.smartScopeId then
            for _, id in ipairs(F.scope_members[tostring(params.smartScopeId)] or {}) do
                if not ids or not opts.honor_ids_with_scope or ids[id] then pool[#pool + 1] = id end
            end
        else
            for id in pairs(F.items) do
                if not ids or ids[id] then pool[#pool + 1] = id end
            end
            table.sort(pool)
        end
        local size, page = params.size or 20, params.page or 1
        local out = {}
        for i = (page - 1) * size + 1, math.min(page * size, #pool) do out[#out + 1] = itemFor(pool[i]) end
        return { items = out, total = #pool, page = page, size = size, hasNext = page * size < #pool }
    end
    return server
end

-- Doble de LuaSettings.
function F.memorySettings(initial)
    local s = { data = initial or {}, flushes = 0 }
    function s:readSetting(k) return self.data[k] end
    function s:saveSetting(k, v) self.data[k] = v; return self end
    function s:flush() self.flushes = self.flushes + 1 end
    return s
end

return F
