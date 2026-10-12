-- bscopes_source.lua -- la fuente "SmartScope de BookOrbit" para Bookshelf
-- (Source API v1, modo list: Bookshelf filtra, ordena y pagina).
--
-- Cada estantería guarda { kind = "bookorbit_scope", scope_id = "18",
-- scope_title = "..." }. list() responde siempre desde la caché local, sin
-- red: es lo que se pinta offline.

local Logic = require("bscopes_logic")

local Source = {}

-- Etiqueta que Bookshelf pone a una estantería recién creada ("New shelf",
-- traducida; "New chip" en versiones antiguas) y el nombre de la fuente.
local AUTO_LABELS = {
    ["New shelf"] = true,
    ["Nueva estantería"] = true,
    ["New chip"] = true,
    ["SmartScope de BookOrbit"] = true,
}

-- deps:
--   store            bscopes_store
--   available()      -> bool   (plugin oficial instalado y con sesión)
--   localMaps()      -> { byBookId = { [bookId] = path } } o nil
--   localProgress(p) -> pct, status   (sidecar de KOReader, solo lectura)
--   exists(p)        -> bool
--   cover(p)         -> bb, w, h   (portada de la caché de Cover browser)
--   chooseScope(scopes, on_choice)  menú para elegir; on_choice(scope|nil)
--   askName(proposed, cb)  pide el nombre de la estantería; cb(texto|nil)
--   ensureScopes(cb) consigue la lista de scopes (red si hace falta); cb(ok)
--   requestSync(opts) lanza una sincronización en segundo plano
--   maybeAutoSync()  sincroniza si la caché es vieja y hay red
--   notify(text)     mensaje breve al usuario
function Source.spec(deps)
    local store = deps.store

    local function recordsFor(source)
        local scope_id = type(source) == "table" and source.scope_id or nil
        if not scope_id then return {} end
        if store:markUsed(scope_id) and deps.requestSync then
            -- Estantería nueva en esta sesión: traer sus libros cuanto antes.
            deps.requestSync({ reason = "new_scope" })
        elseif deps.maybeAutoSync then
            deps.maybeAutoSync()
        end
        local m = store:membership(scope_id)
        if not m then return {} end
        local maps = deps.localMaps and deps.localMaps() or nil
        return Logic.buildRecords(m.ids, maps and maps.byBookId, store:books(),
            deps.localProgress, deps.exists)
    end

    -- Nombres que no ha puesto el usuario: los de Bookshelf para una
    -- estantería nueva y los títulos de scopes (puestos por este plugin).
    local function isAutoLabel(label)
        if label == nil or label == "" or AUTO_LABELS[label] then return true end
        for _, s in ipairs(store:scopes()) do
            if s.title == label then return true end
        end
        return false
    end

    local function startPick(draft, done)
        deps.chooseScope(store:scopes(), function(scope)
            if not scope then return done(false) end
            draft.source.scope_id = scope.id
            draft.source.scope_title = scope.title
            store:markUsed(scope.id)
            if deps.requestSync then deps.requestSync({ reason = "picked" }) end
            local proposed = isAutoLabel(draft.label) and scope.title or draft.label
            if not deps.askName then
                draft.label = proposed
                return done()
            end
            -- El nombre se puede acortar aquí; cancelar deja el propuesto.
            deps.askName(proposed, function(name)
                if type(name) == "string" then name = name:match("^%s*(.-)%s*$") end
                draft.label = (name and name ~= "") and name or proposed
                done()
            end)
        end)
    end

    return {
        api = 1,
        label = function() return "SmartScope de BookOrbit" end,
        available = function() return deps.available() end,
        sort_default = { { key = "title", reverse = false } },

        list = function(source)
            return recordsFor(source)
        end,

        pick = function(draft, done)
            if #store:scopes() > 0 then return startPick(draft, done) end
            deps.ensureScopes(function(ok)
                if ok and #store:scopes() > 0 then
                    startPick(draft, done)
                else
                    deps.notify("No hay lista de SmartScopes guardada. Conecta el wifi una vez y vuelve a intentarlo.")
                    done(false)
                end
            end)
        end,

        refresh = function(_source, _drill, done)
            deps.requestSync({ reason = "refresh", force = true, on_done = function() done() end })
        end,

        cover = function(record)
            if deps.cover and record and record.filepath then
                return deps.cover(record.filepath)
            end
        end,
        -- Sin open ni remote_prefix: son ficheros del Kindle y se abren como
        -- cualquier otro (el plugin oficial sigue preguntando qué posición usar).
    }
end

return Source
