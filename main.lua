-- Estanterías BookOrbit: fuente "SmartScope de BookOrbit" para Bookshelf.
--
-- No sustituye al plugin oficial (BookOrbit Sync): lo usa para hablar con el
-- servidor y para saber qué libro de BookOrbit es cada fichero del Kindle.
-- Este plugin solo lee: no sube progreso ni escribe en los sidecars.

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local Logic = require("bscopes_logic")
local Service = require("bscopes_service")
local Source = require("bscopes_source")

local BookOrbitScopes = WidgetContainer:extend{
    name = "bookorbitscopes",
    is_doc_only = false,
}

local function notify(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 4 })
end

local ERRORS = {
    offline = "Sin conexión: se muestra la última sincronización.",
    bookorbit_unavailable = "El plugin BookOrbit Sync no está activo o no tiene sesión iniciada.",
    client_unavailable = "No se pudo crear el cliente de BookOrbit.",
    cancelled = "Sincronización cancelada.",
    fresh = "Ya estaba sincronizado.",
}

local function errorText(err)
    if ERRORS[err] then return ERRORS[err] end
    if err == 401 or err == 403 then return "BookOrbit rechaza las credenciales (revisa BookOrbit Sync)." end
    return "Error al sincronizar: " .. tostring(err)
end

-- Menú a pantalla completa con las SmartScopes guardadas.
local function chooseScope(scopes, on_choice)
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local chosen, finished = nil, false
    local items = {}
    for _, s in ipairs(scopes) do
        items[#items + 1] = { text = s.title, callback = function() chosen = s end }
    end
    local menu
    menu = Menu:new{
        title = "Elige una SmartScope",
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function()
            if finished then return end
            finished = true
            UIManager:close(menu)
            on_choice(chosen)
        end,
    }
    UIManager:show(menu)
end

-- Nombre de la estantería, con el título de la scope ya escrito.
local function askName(proposed, cb)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = "Nombre de la estantería",
        input = proposed or "",
        allow_newline = false,
        buttons = { {
            {
                text = "Cancelar",
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                    cb(nil)
                end,
            },
            {
                text = "Guardar",
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    cb(text)
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function ensureScopes(cb)
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        Service.requestSync({ force = true, on_done = function(ok) cb(ok) end })
    end)
end

local _spec

local function spec()
    if _spec then return _spec end
    _spec = Source.spec{
        store = Service.store(),
        available = Service.available,
        localMaps = Service.localMaps,
        localProgress = Service.localProgress,
        exists = Service.exists,
        cover = Service.cover,
        chooseScope = chooseScope,
        askName = askName,
        ensureScopes = ensureScopes,
        requestSync = function(opts)
            opts = opts or {}
            local on_done = opts.on_done
            if opts.reason == "refresh" then
                opts.on_done = function(ok, info)
                    if not ok and info ~= "fresh" then notify(errorText(info), 3) end
                    if on_done then on_done(ok, info) end
                end
            end
            return Service.requestSync(opts)
        end,
        maybeAutoSync = Service.maybeAutoSync,
        notify = notify,
    }
    return _spec
end

local function register(ui)
    local bs = ui and ui.bookshelf
    if not (bs and bs.registerSource and (bs.SOURCE_API or 0) >= 1) then return false end
    local ok, why = bs:registerSource(Logic.SOURCE_ID, spec())
    if not ok then
        logger.warn("bookorbit-scopes: Bookshelf rechaza la fuente:", why)
        return false
    end
    Service.setUI(ui)
    return true
end

function BookOrbitScopes:init()
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    -- Los plugins cargan por orden de nombre: Bookshelf puede no estar aún.
    if not register(self.ui) then
        UIManager:nextTick(function()
            if not register(self.ui) then
                logger.info("bookorbit-scopes: Bookshelf no disponible; la fuente no se registra")
            end
        end)
    end
end

function BookOrbitScopes:onNetworkConnected()
    Service.requestSync({ min_interval = Service.NETWORK_INTERVAL, delay = 3 })
end

local function fmtTime(t)
    if not t or t == 0 then return "nunca" end
    return os.date("%d/%m/%Y %H:%M", t)
end

function BookOrbitScopes:statusText()
    local store = Service.store()
    local lines = {
        "Última sincronización: " .. fmtTime(store:lastSync()),
        "Libros del Kindle emparejados: " .. #Service.localIds(),
        "SmartScopes en la lista: " .. #store:scopes(),
    }
    local used = store:usedScopes()
    if #used > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Estanterías:"
        for _, id in ipairs(used) do
            local m = store:membership(id)
            local n = m and #m.ids or 0
            local note = m and m.partial and " (incompleta: scope demasiado grande)" or ""
            lines[#lines + 1] = string.format("  %s: %d libros%s", store:scopeTitle(id) or ("scope " .. id), n, note)
        end
    end
    local err = store:lastError()
    if err then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Último error: " .. err
    end
    if not (self.ui and self.ui.bookshelf) then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Bookshelf no está activo."
    end
    return table.concat(lines, "\n")
end

function BookOrbitScopes:addToMainMenu(menu_items)
    menu_items.bookorbit_scopes = {
        text = "Estanterías BookOrbit",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Sincronizar ahora",
                keep_menu_open = true,
                callback = function()
                    local NetworkMgr = require("ui/network/manager")
                    NetworkMgr:runWhenOnline(function()
                        notify("Sincronizando estanterías…", 2)
                        Service.requestSync({ force = true, on_done = function(ok, info)
                            if ok then
                                notify("Estanterías actualizadas.", 2)
                            else
                                notify(errorText(info))
                            end
                        end })
                    end)
                end,
            },
            {
                text = "Estado",
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{ text = self:statusText() })
                end,
            },
        },
    }
end

return BookOrbitScopes
