-- bscopes_store.lua -- caché offline (settings/bookorbit_scopes.lua).
--
-- Guarda lo último que se supo del servidor: la lista de SmartScopes, los datos
-- de cada libro del Kindle (título, autores, serie, progreso y estado en el
-- servidor) y qué libros del Kindle hay en cada scope usada por una estantería.
-- Sin red, las estanterías se pintan solo con esto.
--
-- Las claves de libros y scopes son cadenas: LuaSettings no conserva bien las
-- tablas con claves numéricas dispersas.

local Store = {}
Store.__index = Store

Store.VERSION = 1

-- settings: objeto con readSetting/saveSetting/flush (LuaSettings en KOReader,
-- un doble en los tests).
function Store.new(settings)
    local self = setmetatable({ settings = settings }, Store)
    if self.settings:readSetting("version") ~= Store.VERSION then
        self.settings:saveSetting("version", Store.VERSION)
    end
    return self
end

function Store:_get(key, default)
    local v = self.settings:readSetting(key)
    if v == nil then return default end
    return v
end

function Store:scopes() return self:_get("scopes", {}) end
function Store:scopesAt() return self:_get("scopes_at", 0) end

function Store:scopeTitle(scope_id)
    for _, s in ipairs(self:scopes()) do
        if s.id == tostring(scope_id) then return s.title end
    end
    return nil
end

function Store:books() return self:_get("books", {}) end

function Store:membership(scope_id)
    local all = self:_get("membership", {})
    return all[tostring(scope_id)]
end

function Store:usedScopes()
    local used = self:_get("used_scopes", {})
    local out = {}
    for id, v in pairs(used) do
        if v then out[#out + 1] = id end
    end
    table.sort(out, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then return na < nb end
        return a < b
    end)
    return out
end

-- Devuelve true si la scope no estaba apuntada (hay que sincronizarla).
function Store:markUsed(scope_id)
    if scope_id == nil then return false end
    local key = tostring(scope_id)
    local used = self:_get("used_scopes", {})
    if used[key] then return false end
    used[key] = true
    self.settings:saveSetting("used_scopes", used)
    self.settings:flush()
    return true
end

function Store:lastSync() return self:_get("last_sync", 0) end
function Store:lastError() return self:_get("last_error", nil) end

function Store:recordError(err, now)
    self.settings:saveSetting("last_error", err and tostring(err) or nil)
    self.settings:saveSetting("last_error_at", now)
    self.settings:flush()
end

-- payload: lo que devuelve Sync.run (ver bscopes_sync.lua).
-- Lo que no llegó (o falló) conserva el valor anterior.
function Store:apply(payload, now)
    if type(payload) ~= "table" then return false end
    local changed = false

    if type(payload.scopes) == "table" and #payload.scopes > 0 then
        self.settings:saveSetting("scopes", payload.scopes)
        self.settings:saveSetting("scopes_at", now)
        changed = true
    end

    if type(payload.books) == "table" then
        local books = self:books()
        for _, b in ipairs(payload.books) do
            if type(b) == "table" and b.id then books[tostring(b.id)] = b end
        end
        -- Fuera los libros que ya no están en el Kindle.
        if type(payload.local_ids) == "table" then
            local keep = {}
            for _, id in ipairs(payload.local_ids) do keep[tostring(id)] = true end
            for key in pairs(books) do
                if not keep[key] then books[key] = nil end
            end
        end
        self.settings:saveSetting("books", books)
        changed = true
    end

    if type(payload.membership) == "table" then
        local all = self:_get("membership", {})
        for _, m in ipairs(payload.membership) do
            if type(m) == "table" and m.scope_id and type(m.ids) == "table" then
                all[tostring(m.scope_id)] = {
                    ids = m.ids,
                    at = now,
                    partial = m.partial == true,
                    mode = m.mode,
                }
                changed = true
            end
        end
        self.settings:saveSetting("membership", all)
    end

    self.settings:saveSetting("last_sync", now)
    if payload.errors and #payload.errors > 0 then
        self.settings:saveSetting("last_error", table.concat(payload.errors, "; "))
        self.settings:saveSetting("last_error_at", now)
    else
        self.settings:saveSetting("last_error", nil)
    end
    self.settings:flush()
    return changed
end

return Store
