-- bscopes_service.lua -- estado compartido de la sesión de KOReader.
--
-- KOReader crea una instancia del plugin para el explorador y otra para el
-- lector; este módulo (cargado una sola vez) guarda lo que tienen que
-- compartir: la caché, la sincronización en curso y la última UI con
-- Bookshelf, para avisarle cuando hay datos nuevos.
--
-- El patrón de sincronización (cliente del plugin oficial, mapas del dispositivo
-- y subproceso) está adaptado de integrations/sui_bookorbit_want.lua de
-- komadorirobin/simpleui.koplugin (licencia MIT).

local logger = require("logger")
local UIManager = require("ui/uimanager")

local Logic = require("bscopes_logic")
local Store = require("bscopes_store")
local Sync = require("bscopes_sync")

local Service = {}

-- Sin red no se hace nada. Con red, como mucho una pasada automática cada
-- AUTO_INTERVAL; al conectar el wifi, si la última tiene más de
-- NETWORK_INTERVAL. Las pedidas a mano (menú, deslizar hacia abajo, elegir
-- scope) siempre se hacen.
Service.AUTO_INTERVAL = 6 * 3600
Service.NETWORK_INTERVAL = 15 * 60

local _store
local _ui
local _running = false
local _listeners = {}
local _progress_cache = {}

function Service.setUI(ui)
    if ui and ui.bookshelf then _ui = ui end
end

function Service.store()
    if _store then return _store end
    local DataStorage = require("datastorage")
    local LuaSettings = require("luasettings")
    local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/bookorbit_scopes.lua")
    _store = Store.new(settings)
    return _store
end

-- Plugin oficial de BookOrbit (instancia actual), o nil.
function Service.bookorbit()
    local ui = _ui
    if ui and ui.bookorbit then return ui.bookorbit end
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok or not PluginLoader or not PluginLoader.getPluginInstance then return nil end
    local ok_i, plugin = pcall(PluginLoader.getPluginInstance, PluginLoader, "bookorbit")
    if ok_i then return plugin end
    return nil
end

function Service.available()
    local plugin = Service.bookorbit()
    if not plugin or type(plugin.newClient) ~= "function" then return false end
    if type(plugin.isLoggedIn) == "function" then
        local ok, logged = pcall(plugin.isLoggedIn, plugin)
        return ok and logged == true
    end
    return true
end

-- Mapa bookId -> ruta que mantiene el plugin oficial (solo ficheros que
-- existen). Lo calcula el propio plugin y lo cachea por generación.
function Service.localMaps()
    local ok, StateManager = pcall(require, "bookorbit_state_manager")
    if not ok or not StateManager or type(StateManager.onDeviceMaps) ~= "function" then return nil end
    local ok_m, maps = pcall(StateManager.onDeviceMaps)
    if ok_m and type(maps) == "table" then return maps end
    return nil
end

function Service.localIds()
    local maps = Service.localMaps()
    local ids = {}
    for id in pairs(maps and maps.byBookId or {}) do
        local n = tonumber(id)
        if n then ids[#ids + 1] = n end
    end
    table.sort(ids)
    return ids
end

function Service.exists(path)
    local lfs = require("libs/libkoreader-lfs")
    return type(path) == "string" and lfs.attributes(path, "mode") == "file"
end

-- Progreso y estado del sidecar de KOReader, solo lectura. Se cachea por la
-- fecha de modificación del sidecar para no abrirlo en cada repintado.
function Service.localProgress(path)
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds then return nil end
    local sidecar = DocSettings:findSidecarFile(path)
    if not sidecar then
        _progress_cache[path] = nil
        return nil
    end
    local lfs = require("libs/libkoreader-lfs")
    local mtime = lfs.attributes(sidecar, "modification")
    local hit = _progress_cache[path]
    if hit and hit.sidecar == sidecar and hit.mtime == mtime then
        return hit.pct, hit.status
    end
    local ok, ds = pcall(DocSettings.open, DocSettings, path)
    if not ok or not ds then return nil end
    local pct = ds:readSetting("percent_finished")
    local summary = ds:readSetting("summary")
    local status = Logic.mapLocalStatus(type(summary) == "table" and summary.status or nil)
    _progress_cache[path] = { sidecar = sidecar, mtime = mtime, pct = pct, status = status }
    return pct, status
end

-- Portada desde la caché de Cover browser. getBookInfo devuelve un
-- blitbuffer nuevo en cada llamada, que Bookshelf libera tras pintarlo.
function Service.cover(path)
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok or not BookInfoManager then return nil end
    local ok_i, info = pcall(BookInfoManager.getBookInfo, BookInfoManager, path, true)
    if ok_i and type(info) == "table" and info.cover_bb then
        return info.cover_bb, info.cover_w, info.cover_h
    end
    return nil
end

-- Portada de la tarjeta de una SmartScope en una estantería de pila: la del
-- primer libro (de paths) que tenga portada en la caché de Cover browser,
-- guardada como PNG en cache/bookorbit-scopes/. Solo se regenera si cambia el
-- libro elegido o falta el archivo.
local _folder_covers = {}

function Service.coverDir()
    local DataStorage = require("datastorage")
    return DataStorage:getDataDir() .. "/cache/bookorbit-scopes"
end

function Service.folderCover(scope_id, paths)
    local lfs = require("libs/libkoreader-lfs")
    local file = Service.coverDir() .. "/scope-" .. tostring(scope_id):gsub("[^%w_-]", "_") .. ".png"
    local hit = _folder_covers[scope_id]
    if hit and lfs.attributes(file, "mode") == "file" then
        for _, p in ipairs(paths or {}) do
            if p == hit.book then return file end
        end
    end
    for _, p in ipairs(paths or {}) do
        local bb = Service.cover(p)
        if bb then
            lfs.mkdir(Service.coverDir():match("^(.*)/[^/]+$"))
            lfs.mkdir(Service.coverDir())
            local ok = pcall(bb.writePNG, bb, file)
            pcall(bb.free, bb)
            if ok and lfs.attributes(file, "mode") == "file" then
                _folder_covers[scope_id] = { book = p }
                return file
            end
            return nil
        end
    end
    return nil
end

function Service.connected()
    local ok_n, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok_n then return false end
    local ok, value = pcall(NetworkMgr.isConnected, NetworkMgr)
    return ok and value == true
end

function Service.notifyBookshelf()
    local ui = _ui
    if ui and ui.bookshelf and type(ui.bookshelf.sourceChanged) == "function" then
        pcall(ui.bookshelf.sourceChanged, ui.bookshelf, Logic.SOURCE_ID)
        pcall(ui.bookshelf.sourceChanged, ui.bookshelf, Logic.STACK_SOURCE_ID)
    end
end

local function finish(ok, info)
    _running = false
    local listeners = _listeners
    _listeners = {}
    UIManager:nextTick(function()
        for _, fn in ipairs(listeners) do pcall(fn, ok, info) end
    end)
end

local function runSync()
    local plugin = Service.bookorbit()
    if not plugin or type(plugin.newClient) ~= "function" then
        return finish(false, "bookorbit_unavailable")
    end
    local ok_c, client = pcall(plugin.newClient, plugin)
    if not ok_c or not client then return finish(false, "client_unavailable") end

    local store = Service.store()
    local opts = {
        local_ids = Service.localIds(),
        scope_ids = store:usedScopes(),
        all_scopes = store:usesAll(),
        with_scopes = true,
    }
    local completed, result = client:runInSubprocess(function()
        return Sync.run(client, opts)
    end)
    if not completed then return finish(false, "cancelled") end
    if not result or type(result.body) ~= "table" then
        local err = result and result.err or "request_failed"
        store:recordError(err, os.time())
        return finish(false, err)
    end
    local payload = result.body
    store:apply(payload, os.time())
    logger.info("bookorbit-scopes: sincronizado,", #(payload.local_ids or {}), "libros,",
        #(payload.membership or {}), "scopes,", payload.requests or 0, "peticiones")
    Service.notifyBookshelf()
    finish(true, payload)
end

-- opts: force (ignora los intervalos), on_done(ok, info).
function Service.requestSync(opts)
    opts = opts or {}
    if type(opts.on_done) == "function" then _listeners[#_listeners + 1] = opts.on_done end
    if _running then return true end
    if not Service.connected() then
        finish(false, "offline")
        return false
    end
    if not Service.available() then
        finish(false, "bookorbit_unavailable")
        return false
    end
    local interval = opts.min_interval
    if not opts.force and interval and (os.time() - Service.store():lastSync()) < interval then
        finish(false, "fresh")
        return false
    end
    _running = true
    UIManager:scheduleIn(opts.delay or 0.2, function()
        if not Service.connected() then return finish(false, "offline") end
        local function run()
            local ok, err = pcall(runSync)
            if not ok then
                logger.warn("bookorbit-scopes: fallo al sincronizar:", tostring(err))
                finish(false, tostring(err))
            end
        end
        local ok_t, Trapper = pcall(require, "ui/trapper")
        if ok_t and Trapper and Trapper.wrap then Trapper:wrap(run) else run() end
    end)
    return true
end

function Service.maybeAutoSync()
    if _running then return end
    if (os.time() - Service.store():lastSync()) < Service.AUTO_INTERVAL then return end
    if not Service.connected() then return end
    Service.requestSync({ min_interval = Service.AUTO_INTERVAL })
end

function Service.isRunning() return _running end

return Service
