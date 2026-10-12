-- bscopes_logic.lua -- lógica pura (sin KOReader) de las estanterías SmartScope.
--
-- Todo lo que decide qué libro va en qué estantería y con qué progreso vive
-- aquí, para poder probarlo en el Mac con LuaJIT sin un KOReader de por medio.

local M = {}

-- Id de la fuente en Bookshelf. Es lo que cada estantería guarda como
-- source.kind: no cambiarlo nunca o las estanterías dejarían de encontrarla.
M.SOURCE_ID = "bookorbit_scope"
-- Fuente de "pila": una estantería con varias SmartScopes como carpetas.
M.STACK_SOURCE_ID = "bookorbit_scope_stack"

-- El catálogo de KOReader admite size <= 100 e ids <= 200 por petición.
M.PAGE_SIZE = 100
-- Tope de páginas al recorrer una SmartScope entera (cuando el servidor no
-- aplica el filtro ids junto a smartScopeId). 60 x 100 = 6.000 libros.
M.MAX_SCAN_PAGES = 60

-- Estados de BookOrbit (ReadStatus): unread, want_to_read, reading, on_hold,
-- read, abandoned, más rereading y skimmed. Bookshelf solo entiende
-- "unread", "reading" y "finished".
local SERVER_STATUS = {
    read = "finished",
    finished = "finished",
    reading = "reading",
    rereading = "reading",
    skimmed = "reading",
    on_hold = "reading",
    unread = "unread",
    want_to_read = "unread",
    abandoned = "unread",
}

function M.mapServerStatus(raw)
    if type(raw) ~= "string" then return nil end
    return SERVER_STATUS[raw]
end

-- summary.status de KOReader: "reading", "complete", "abandoned" (en pausa).
local LOCAL_STATUS = {
    complete = "finished",
    finished = "finished",
    reading = "reading",
    abandoned = "reading",
    on_hold = "reading",
}

function M.mapLocalStatus(raw)
    if type(raw) ~= "string" then return nil end
    return LOCAL_STATUS[raw]
end

local function clampPct(p)
    p = tonumber(p)
    if not p or p ~= p then return nil end
    if p < 0 then return 0 end
    if p > 1 then return 1 end
    return p
end

-- El catálogo devuelve progressPercentage en escala 0-100 (p. ej. 71.83).
function M.serverPct(progress_percentage)
    local p = tonumber(progress_percentage)
    if not p then return nil end
    return clampPct(p / 100)
end

-- Progreso que se pinta en la estantería: el mayor entre servidor y dispositivo.
-- Estado: terminado si cualquiera de los dos lo da por terminado; leyendo si
-- alguno está leyendo o hay progreso; si no, sin empezar.
function M.mergeProgress(server_pct, server_status, local_pct, local_status)
    local s, l = clampPct(server_pct), clampPct(local_pct)
    local pct
    if s and l then pct = math.max(s, l) else pct = s or l end
    local status
    if server_status == "finished" or local_status == "finished" then
        status = "finished"
    elseif server_status == "reading" or local_status == "reading" or (pct and pct > 0) then
        status = "reading"
    else
        status = "unread"
    end
    return pct, status
end

-- Días desde 1970-01-01 para una fecha civil (algoritmo de Howard Hinnant).
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- "2026-10-07T22:38:44.930Z" -> segundos Unix (UTC). nil si no se entiende.
function M.parseIsoTime(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, h, mi, se = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if not y then return nil end
    local secs = daysFromCivil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
        + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
    -- Desfase explícito (+02:00); "Z" o nada es UTC.
    local sign, oh, om = s:match("([%+%-])(%d%d):?(%d%d)$")
    if sign and not s:match("Z$") then
        local off = tonumber(oh) * 3600 + tonumber(om) * 60
        secs = (sign == "+") and (secs - off) or (secs + off)
    end
    return secs
end

function M.chunk(list, n)
    local out, cur = {}, {}
    for _, v in ipairs(list or {}) do
        cur[#cur + 1] = v
        if #cur >= n then out[#out + 1] = cur; cur = {} end
    end
    if #cur > 0 then out[#out + 1] = cur end
    return out
end

-- Libro del catálogo -> lo que guardamos en caché (solo valores planos).
function M.normalizeBook(item)
    if type(item) ~= "table" or tonumber(item.id) == nil then return nil end
    local authors = {}
    for _, a in ipairs(type(item.authors) == "table" and item.authors or {}) do
        local name = type(a) == "table" and (a.name or a.displayName) or a
        if type(name) == "string" and name ~= "" then authors[#authors + 1] = name end
    end
    local series_num
    if item.seriesIndex ~= nil and item.seriesIndex ~= false then
        local n = tonumber(item.seriesIndex)
        if n then
            series_num = (n == math.floor(n)) and string.format("%d", n) or tostring(n)
        end
    end
    return {
        id = tonumber(item.id),
        title = type(item.title) == "string" and item.title or nil,
        authors = authors,
        series_name = type(item.seriesName) == "string" and item.seriesName or nil,
        series_num = series_num,
        pct = M.serverPct(item.progressPercentage),
        status = M.mapServerStatus(item.readStatus),
        last_read = M.parseIsoTime(item.lastReadAt),
        added = M.parseIsoTime(item.addedAt),
    }
end

-- Lista de SmartScopes de /catalog/sections/smart-scopes -> {id, title, icon}.
function M.normalizeScopes(body)
    local out = {}
    for _, it in ipairs(type(body) == "table" and type(body.items) == "table" and body.items or {}) do
        if type(it) == "table" and it.id ~= nil and type(it.title) == "string" then
            out[#out + 1] = {
                id = tostring(it.id),
                title = it.title,
                icon = type(it.icon) == "string" and it.icon or nil,
            }
        end
    end
    return out
end

-- Qué libros del dispositivo pertenecen a una SmartScope.
--
-- fetchPage(params) -> body, err  (body = respuesta de /catalog/books)
-- local_ids: lista de bookId del dispositivo.
--
-- Primero se pide la scope filtrada por los ids del dispositivo, de 100 en 100.
-- BookOrbit 3.3.0 ignora ids cuando va con smartScopeId (opds-book.service:
-- buildCatalogScope sale antes de añadir la cláusula ids). Si la respuesta trae
-- algún libro que no está en el dispositivo, o dice que hay más páginas, es que el
-- filtro no se ha aplicado: entonces se recorre la scope completa, una sola
-- vez, y se cruza en local. Si el servidor algún día lo aplica, se usa la vía
-- corta sin tocar nada.
--
-- Devuelve: ids (lista ordenada), info { mode = "ids"|"scan", partial = bool,
-- pages = n, books = {item,...} } o nil, err.
function M.collectScopeMembers(fetchPage, scope_id, local_ids, opts)
    opts = opts or {}
    local page_size = opts.page_size or M.PAGE_SIZE
    local max_pages = opts.max_scan_pages or M.MAX_SCAN_PAGES
    local local_set = {}
    for _, id in ipairs(local_ids or {}) do local_set[tonumber(id)] = true end

    local found, seen_items = {}, {}
    local function keep(item)
        local id = tonumber(item.id)
        if id and local_set[id] and not found[id] then
            found[id] = true
            seen_items[#seen_items + 1] = item
        end
    end
    local function result(mode, partial, pages)
        local ids = {}
        for id in pairs(found) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids, { mode = mode, partial = partial, pages = pages, books = seen_items }
    end

    if #(local_ids or {}) == 0 then return result("ids", false, 0) end

    local pages = 0
    for _, chunk in ipairs(M.chunk(local_ids, page_size)) do
        local chunk_set = {}
        for _, id in ipairs(chunk) do chunk_set[tonumber(id)] = true end
        local params = {
            smartScopeId = scope_id,
            ids = table.concat(chunk, ","),
            size = page_size,
            page = 1,
            sort = "title",
        }
        local body, err = fetchPage(params)
        pages = pages + 1
        if type(body) ~= "table" then return nil, err or "request_failed" end
        local items = type(body.items) == "table" and body.items or {}
        local foreign = false
        for _, item in ipairs(items) do
            if not chunk_set[tonumber(item.id)] then foreign = true end
            keep(item)
        end
        if foreign or body.hasNext == true then
            -- Filtro ids ignorado: la página 1 ya es la scope completa
            -- (las demás peticiones por ids devolverían lo mismo).
            local page = 1
            local has_next = body.hasNext == true
            while has_next do
                if page >= max_pages then return result("scan", true, pages) end
                page = page + 1
                params.page = page
                local b, e = fetchPage(params)
                pages = pages + 1
                if type(b) ~= "table" then return nil, e or "request_failed" end
                for _, item in ipairs(type(b.items) == "table" and b.items or {}) do keep(item) end
                has_next = b.hasNext == true
            end
            return result("scan", false, pages)
        end
    end
    return result("ids", false, pages)
end

local function basename(path)
    return (path:match("([^/]+)$") or path)
end

local function stripExt(name)
    return (name:gsub("%.[^%.]+$", ""))
end

function M.formatOf(path)
    local ext = type(path) == "string" and path:match("%.([^%./]+)$")
    return ext and ext:upper() or nil
end

-- Registros para Bookshelf.
--
-- member_ids: bookId de la scope que están en el dispositivo (de la caché).
-- by_book_id: mapa bookId -> ruta del fichero (del plugin oficial).
-- books: caché de libros por tostring(bookId) (normalizeBook).
-- localProgress(path) -> pct, status (del sidecar) o nil.
-- exists(path) -> bool.
function M.buildRecords(member_ids, by_book_id, books, localProgress, exists)
    local out = {}
    by_book_id = type(by_book_id) == "table" and by_book_id or {}
    books = type(books) == "table" and books or {}
    for _, raw in ipairs(member_ids or {}) do
        local id = tonumber(raw)
        local path = id and (by_book_id[id] or by_book_id[tostring(id)])
        if path and (not exists or exists(path)) then
            local b = books[tostring(id)] or {}
            local lpct, lstatus
            if localProgress then lpct, lstatus = localProgress(path) end
            local pct, status = M.mergeProgress(b.pct, b.status, lpct, lstatus)
            local title = b.title or stripExt(basename(path))
            local authors = {}
            for i, a in ipairs(b.authors or {}) do authors[i] = a end
            out[#out + 1] = {
                filepath = path,
                title = title,
                display_title = title,
                author = authors[1],
                authors = authors,
                series_name = b.series_name,
                series_num = b.series_num,
                book_pct = pct,
                percent_finished = pct,
                status = status,
                read_status = status,
                last_read_time = b.last_read,
                last_opened = b.last_read,
                added_time = b.added,
                format = M.formatOf(path),
                bookorbit_id = id,
            }
        end
    end
    return out
end

-- Clave de orden para títulos: minúsculas y sin tildes, para que "Ángel"
-- vaya con la A y no al final.
local FOLD = {
    ["á"] = "a", ["à"] = "a", ["ä"] = "a", ["â"] = "a", ["Á"] = "a", ["À"] = "a", ["Ä"] = "a", ["Â"] = "a",
    ["é"] = "e", ["è"] = "e", ["ë"] = "e", ["ê"] = "e", ["É"] = "e", ["È"] = "e", ["Ë"] = "e", ["Ê"] = "e",
    ["í"] = "i", ["ì"] = "i", ["ï"] = "i", ["î"] = "i", ["Í"] = "i", ["Ì"] = "i", ["Ï"] = "i", ["Î"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ö"] = "o", ["ô"] = "o", ["Ó"] = "o", ["Ò"] = "o", ["Ö"] = "o", ["Ô"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["ü"] = "u", ["û"] = "u", ["Ú"] = "u", ["Ù"] = "u", ["Ü"] = "u", ["Û"] = "u",
    ["ñ"] = "n", ["Ñ"] = "n", ["ç"] = "c", ["Ç"] = "c", ["¿"] = "", ["¡"] = "",
}
function M.sortKey(s)
    s = tostring(s or "")
    s = s:gsub("[\195\194][\128-\191]", function(c) return FOLD[c] or c end)
    return s:lower()
end

function M.sortByTitle(list, field)
    field = field or "title"
    table.sort(list, function(a, b)
        local ka, kb = M.sortKey(a[field]), M.sortKey(b[field])
        if ka ~= kb then return ka < kb end
        return tostring(a[field]) < tostring(b[field])
    end)
    return list
end

-- SmartScopes que se muestran como carpetas en una estantería de pila.
--
-- scopes: lista {id, title} (de la caché).
-- selected: nil = todas; o lista de ids elegidos.
-- membership(id) -> { ids = {...} } o nil.
-- by_book_id, exists: como en buildRecords.
-- Con "todas" se ocultan las scopes sin libros en el dispositivo; las
-- elegidas a mano se muestran siempre (aunque tengan 0).
-- Devuelve { {scope_id, title, count, paths = {...}} } ordenado por título.
function M.scopeFolders(scopes, selected, membership, by_book_id, exists)
    by_book_id = type(by_book_id) == "table" and by_book_id or {}
    local want
    if type(selected) == "table" then
        want = {}
        for _, id in ipairs(selected) do want[tostring(id)] = true end
    end
    local out = {}
    for _, s in ipairs(scopes or {}) do
        local id = tostring(s.id)
        if not want or want[id] then
            local m = membership(id)
            local paths = {}
            for _, raw in ipairs(m and m.ids or {}) do
                local n = tonumber(raw)
                local path = n and (by_book_id[n] or by_book_id[tostring(n)])
                if path and (not exists or exists(path)) then paths[#paths + 1] = path end
            end
            if want or #paths > 0 then
                out[#out + 1] = { scope_id = id, title = s.title, count = #paths, paths = paths,
                    synced = m ~= nil }
            end
        end
    end
    return M.sortByTitle(out)
end

-- Registro de carpeta para Bookshelf (modo fetch). El número de libros va en
-- el título: el contador de carpetas de Bookshelf viene desactivado de serie.
function M.folderRecord(entry, title_fmt, cover_path)
    local title = (title_fmt or "%1 (%2)"):gsub("%%1", (entry.title:gsub("%%", "%%%%"))):gsub("%%2", tostring(entry.count))
    return {
        is_folder = true,
        id = "scope-" .. entry.scope_id,
        title = title,
        label = title,
        display_title = title,
        cover_image_path = cover_path,
        scope_id = entry.scope_id,
        drill = { label = entry.title, scope_id = entry.scope_id },
    }
end

function M.slice(list, offset, limit)
    local out = {}
    offset = offset or 0
    local last = limit and math.min(offset + limit, #list) or #list
    for i = offset + 1, last do out[#out + 1] = list[i] end
    return out
end

return M
