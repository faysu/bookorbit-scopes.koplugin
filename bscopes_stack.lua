-- bscopes_stack.lua -- fuente "pila de SmartScopes" para Bookshelf
-- (Source API v1, modo fetch: carpetas que se abren).
--
-- Una estantería de este tipo muestra una carpeta por SmartScope, con el
-- número de libros del dispositivo en el título y la portada de uno de ellos.
-- Al abrir una carpeta se ven sus libros. Como la estantería de Géneros, pero
-- con las SmartScopes de BookOrbit.
--
-- source = { kind = "bookorbit_scope_stack", mode = "all" }
--        o { kind = ..., mode = "selected", scope_ids = { "6", "22" } }
-- Todo sale de la caché local: funciona sin red.

local I18n = require("bscopes_i18n")
local Logic = require("bscopes_logic")

local _ = I18n.gettext
local T = I18n.template

local Stack = {}

-- Nombres que no ha puesto el usuario (para no pisar uno propio).
local function autoLabels(store)
    local set = {}
    for _i, key in ipairs({ "BookOrbit SmartScopes", "BookOrbit SmartScopes (stack)" }) do
        for _j, form in ipairs(I18n.allForms(key)) do set[form] = true end
    end
    for _i, key in ipairs({ "New shelf", "Nueva estantería", "New chip" }) do set[key] = true end
    for _i, s in ipairs(store:scopes()) do set[s.title] = true end
    return set
end

-- Texto del botón del editor: "SmartScopes: todas" / "SmartScopes: 3 elegidas".
function Stack.summary(source)
    if type(source) ~= "table" or source.mode ~= "selected" then
        return _("SmartScopes: all")
    end
    return T(_("SmartScopes: %1 selected"), #(source.scope_ids or {}))
end

-- deps (como bscopes_source, más):
--   chooseScopeSet(scopes, current_source, cb)  cb({mode="all"} |
--       {mode="selected", scope_ids={...}} | nil)
--   folderCover(scope_id, paths) -> ruta de imagen o nil
function Stack.spec(deps)
    local store = deps.store

    local function ensureUsed(source)
        local fresh = false
        if source.mode == "selected" then
            for _i, id in ipairs(source.scope_ids or {}) do
                if store:markUsed(id) then fresh = true end
            end
        elseif store:markAllUsed() then
            fresh = true
        end
        if fresh and deps.requestSync then
            deps.requestSync({ reason = "new_scope" })
        elseif deps.maybeAutoSync then
            deps.maybeAutoSync()
        end
    end

    local function bookRecords(scope_id)
        local m = store:membership(scope_id)
        if not m then return {} end
        local maps = deps.localMaps and deps.localMaps() or nil
        local recs = Logic.buildRecords(m.ids, maps and maps.byBookId, store:books(),
            deps.localProgress, deps.exists)
        return Logic.sortByTitle(recs)
    end

    local function folders(source)
        local maps = deps.localMaps and deps.localMaps() or nil
        local selected = source.mode == "selected" and (source.scope_ids or {}) or nil
        return Logic.scopeFolders(store:scopes(), selected,
            function(id) return store:membership(id) end,
            maps and maps.byBookId, deps.exists)
    end

    local function applySelection(draft, sel)
        draft.source.mode = sel.mode
        draft.source.scope_ids = sel.mode == "selected" and sel.scope_ids or nil
        if sel.mode == "selected" then
            for _i, id in ipairs(sel.scope_ids or {}) do store:markUsed(id) end
        else
            store:markAllUsed()
        end
        if deps.requestSync then deps.requestSync({ reason = "picked" }) end
    end

    local function startPick(draft, done)
        deps.chooseScopeSet(store:scopes(), draft.source, function(sel)
            if not sel then return done(false) end
            applySelection(draft, sel)
            local cur = draft.label
            local proposed = (cur == nil or cur == "" or autoLabels(store)[cur])
                and _("BookOrbit SmartScopes") or cur
            if not deps.askName then
                draft.label = proposed
                return done()
            end
            deps.askName(proposed, function(name)
                if type(name) == "string" then name = name:match("^%s*(.-)%s*$") end
                draft.label = (name and name ~= "") and name or proposed
                done()
            end)
        end)
    end

    return {
        api = 1,
        label = function() return _("BookOrbit SmartScopes (stack)") end,
        available = function() return deps.available() end,

        fetch = function(source, drill, offset, limit)
            source = source or {}
            ensureUsed(source)
            if drill and drill.scope_id then
                local recs = bookRecords(drill.scope_id)
                local page = Logic.slice(recs, offset, limit)
                if deps.cover then
                    for _i, rec in ipairs(page) do
                        local bb, w, h = deps.cover(rec.filepath)
                        if bb then
                            rec.cover_bb, rec.cover_w, rec.cover_h, rec.has_cover = bb, w, h, true
                        end
                    end
                end
                return page, #recs
            end
            local entries = folders(source)
            local page = {}
            for _i, e in ipairs(Logic.slice(entries, offset, limit)) do
                local cover = deps.folderCover and deps.folderCover(e.scope_id, e.paths) or nil
                page[#page + 1] = Logic.folderRecord(e, _("%1 (%2)"), cover)
            end
            return page, #entries
        end,

        open_folder = function(record)
            return record and record.drill
        end,

        pick = function(draft, done)
            if #store:scopes() > 0 then return startPick(draft, done) end
            deps.ensureScopes(function(ok)
                if ok and #store:scopes() > 0 then
                    startPick(draft, done)
                else
                    deps.notify(_("No saved SmartScope list. Connect to Wi-Fi once and try again."))
                    done(false)
                end
            end)
        end,

        -- En el editor de la estantería, en lugar de "Orden del servidor":
        -- cambiar qué SmartScopes se muestran.
        editor_rows = function(draft)
            return { {
                {
                    text = function(d) return Stack.summary(d.source) end,
                    callback = function(d, done)
                        deps.chooseScopeSet(store:scopes(), d.source, function(sel)
                            if sel then applySelection(d, sel) end
                            done()
                        end)
                    end,
                },
            } }
        end,

        refresh = function(_source, _drill, done)
            deps.requestSync({ reason = "refresh", force = true, on_done = function() done() end })
        end,
    }
end

return Stack
