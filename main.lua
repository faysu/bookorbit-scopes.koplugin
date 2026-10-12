-- Estanterías BookOrbit: fuente "SmartScope de BookOrbit" para Bookshelf.
--
-- No sustituye al plugin oficial (BookOrbit Sync): lo usa para hablar con el
-- servidor y para saber qué libro de BookOrbit es cada fichero del dispositivo.
-- Este plugin solo lee: no sube progreso ni escribe en los sidecars.

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local I18n = require("bscopes_i18n")
local Logic = require("bscopes_logic")
local Service = require("bscopes_service")
local Source = require("bscopes_source")
local Stack = require("bscopes_stack")

local _ = I18n.gettext
local T = I18n.template

local BookOrbitScopes = WidgetContainer:extend{
    name = "bookorbitscopes",
    is_doc_only = false,
}

local function notify(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 4 })
end

local ERRORS = {
    offline = "Offline: showing the last sync.",
    bookorbit_unavailable = "The BookOrbit Sync plugin is not enabled or not logged in.",
    client_unavailable = "Could not create the BookOrbit client.",
    cancelled = "Sync cancelled.",
    fresh = "Already up to date.",
}

local function errorText(err)
    if ERRORS[err] then return _(ERRORS[err]) end
    if err == 401 or err == 403 then return _("BookOrbit rejected the credentials (check BookOrbit Sync).") end
    return T(_("Sync error: %1"), tostring(err))
end

-- Menú a pantalla completa con las SmartScopes guardadas.
local function chooseScope(scopes, on_choice)
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local chosen, finished = nil, false
    local items = {}
    for _i, s in ipairs(scopes) do
        items[#items + 1] = { text = s.title, callback = function() chosen = s end }
    end
    local menu
    menu = Menu:new{
        title = _("Choose a SmartScope"),
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

-- Menú a pantalla completa que NO se cierra al tocar una opción (para las
-- casillas). on_close(true) si se cerró con la X / atrás.
local function stickyMenu(title, items)
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    -- Menu:onMenuSelect llamaría a close_callback tras cada toque.
    menu.onMenuSelect = function(_m, item)
        if item.callback then item.callback() end
        return true
    end
    return menu
end

-- Qué SmartScopes muestra una estantería de pila: todas, o las que se marquen.
-- cb({ mode = "all" }) | cb({ mode = "selected", scope_ids = {...} }) | cb(nil)
local function chooseScopeSet(scopes, current, cb)
    current = current or {}
    local finished = false
    local function finish(sel)
        if finished then return end
        finished = true
        cb(sel)
    end

    local function checklist(parent)
        local checked = {}
        if current.mode == "selected" then
            for _i, id in ipairs(current.scope_ids or {}) do checked[tostring(id)] = true end
        end
        local menu
        local items = {}
        local function count()
            local n = 0
            for _k, v in pairs(checked) do if v then n = n + 1 end end
            return n
        end
        local function doneText() return "✓ " .. T(_("OK (%1 selected)"), count()) end
        local function accept()
            local ids = {}
            for _i, s in ipairs(scopes) do
                if checked[s.id] then ids[#ids + 1] = s.id end
            end
            UIManager:close(menu)
            if parent then UIManager:close(parent) end
            finish({ mode = "selected", scope_ids = ids })
        end
        items[1] = {
            text = doneText(),
            bold = true,
            callback = function()
                if count() == 0 then
                    notify(_("Choose at least one SmartScope."), 2)
                    return
                end
                accept()
            end,
        }
        for _i, s in ipairs(scopes) do
            local item = {}
            local function label() return s.title .. (checked[s.id] and "  ✓" or "") end
            item.text = label()
            item.callback = function()
                checked[s.id] = not checked[s.id]
                item.text = label()
                items[1].text = doneText()
                menu:updateItems(nil, true)
            end
            items[#items + 1] = item
        end
        menu = stickyMenu(_("Choose SmartScopes"), items)
        -- Como en las casillas de KOReader, cerrar guarda lo marcado. Sin
        -- nada marcado, vuelve al primer menú sin cambiar nada.
        menu.close_callback = function()
            if finished then return end
            if count() > 0 then return accept() end
            UIManager:close(menu)
            if not parent then finish(nil) end
        end
        UIManager:show(menu)
    end

    local first
    local items = {
        {
            text = _("All SmartScopes") .. (current.mode ~= "selected" and current.mode and "  ✓" or ""),
            callback = function()
                UIManager:close(first)
                finish({ mode = "all" })
            end,
        },
        {
            text = _("Choose SmartScopes…") .. (current.mode == "selected" and "  ✓" or ""),
            callback = function() checklist(first) end,
        },
    }
    first = stickyMenu(_("SmartScopes on this shelf"), items)
    first.close_callback = function()
        UIManager:close(first)
        finish(nil)
    end
    UIManager:show(first)
end

-- Nombre de la estantería, con el título de la scope ya escrito.
local function askName(proposed, cb)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Shelf name"),
        input = proposed or "",
        allow_newline = false,
        buttons = { {
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                    cb(nil)
                end,
            },
            {
                text = _("Save"),
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

local _spec, _stack_spec

local function deps()
    return {
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
        chooseScopeSet = chooseScopeSet,
        folderCover = Service.folderCover,
    }
end

local function spec()
    if not _spec then _spec = Source.spec(deps()) end
    return _spec
end

local function stackSpec()
    if not _stack_spec then _stack_spec = Stack.spec(deps()) end
    return _stack_spec
end

local function register(ui)
    local bs = ui and ui.bookshelf
    if not (bs and bs.registerSource and (bs.SOURCE_API or 0) >= 1) then return false end
    local ok, why = bs:registerSource(Logic.SOURCE_ID, spec())
    if not ok then
        logger.warn("bookorbit-scopes: Bookshelf rechaza la fuente:", why)
        return false
    end
    local ok2, why2 = bs:registerSource(Logic.STACK_SOURCE_ID, stackSpec())
    if not ok2 then
        logger.warn("bookorbit-scopes: Bookshelf rechaza la fuente de pila:", why2)
    end
    Service.setUI(ui)
    -- Al arrancar, Bookshelf puede haber abierto ya la última estantería
    -- (vacía, porque la fuente aún no existía): que la vuelva a pintar.
    Service.notifyBookshelf()
    return true
end

-- Reintentos si Bookshelf tarda en cargar.
local RETRY_DELAYS = { 1, 3 }

-- Este plugin se inicia antes que Bookshelf (orden alfabético de carpetas), y
-- Bookshelf crea su pantalla en el evento Show, antes de cualquier nextTick.
-- En la vista de lomos guarda la lista de cada estantería 30 s y sourceChanged
-- no la renueva, así que registrarse tarde deja la estantería vacía ese rato.
-- Por eso el registro va en el postInitCallback de la UI (cuando ya están
-- todos los plugins y aún no se ha mostrado nada); onShow y los reintentos
-- quedan de respaldo.
function BookOrbitScopes:init()
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    if self:_register() then return end
    if self.ui and type(self.ui.registerPostInitCallback) == "function" then
        pcall(self.ui.registerPostInitCallback, self.ui, function() self:_register() end)
    end
    local attempt = 0
    local function retry()
        if self:_register() then return end
        attempt = attempt + 1
        if RETRY_DELAYS[attempt] then
            UIManager:scheduleIn(RETRY_DELAYS[attempt], retry)
        else
            logger.info("bookorbit-scopes: Bookshelf no disponible; la fuente no se registra")
        end
    end
    UIManager:nextTick(retry)
end

function BookOrbitScopes:_register()
    if self._registered then return true end
    self._registered = register(self.ui)
    return self._registered
end

-- Llega antes que el onShow de Bookshelf (mismo orden que init). No devuelve
-- true para no cortar el evento.
function BookOrbitScopes:onShow()
    self:_register()
end

function BookOrbitScopes:onNetworkConnected()
    Service.requestSync({ min_interval = Service.NETWORK_INTERVAL, delay = 3 })
end

local function fmtTime(t)
    if not t or t == 0 then return _("never") end
    return os.date("%Y-%m-%d %H:%M", t)
end

function BookOrbitScopes:statusText()
    local store = Service.store()
    local lines = {
        T(_("Last sync: %1"), fmtTime(store:lastSync())),
        T(_("Matched books on this device: %1"), #Service.localIds()),
        T(_("SmartScopes in the list: %1"), #store:scopes()),
    }
    local used = store:usedScopes()
    if #used > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Shelves:")
        for _i, id in ipairs(used) do
            local m = store:membership(id)
            local n = m and #m.ids or 0
            local note = m and m.partial and _(" (incomplete: SmartScope too large)") or ""
            lines[#lines + 1] = "  " .. T(_("%1: %2 books"), store:scopeTitle(id) or T(_("scope %1"), id), n) .. note
        end
    end
    local err = store:lastError()
    if err then
        lines[#lines + 1] = ""
        lines[#lines + 1] = T(_("Last error: %1"), err)
    end
    if not (self.ui and self.ui.bookshelf) then
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("Bookshelf is not active.")
    end
    return table.concat(lines, "\n")
end

function BookOrbitScopes:addToMainMenu(menu_items)
    menu_items.bookorbit_scopes = {
        text = _("BookOrbit shelves"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Sync now"),
                keep_menu_open = true,
                callback = function()
                    local NetworkMgr = require("ui/network/manager")
                    NetworkMgr:runWhenOnline(function()
                        notify(_("Syncing shelves…"), 2)
                        Service.requestSync({ force = true, on_done = function(ok, info)
                            if ok then
                                notify(_("Shelves updated."), 2)
                            else
                                notify(errorText(info))
                            end
                        end })
                    end)
                end,
            },
            {
                text = _("Status"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{ text = self:statusText() })
                end,
            },
        },
    }
end

return BookOrbitScopes
