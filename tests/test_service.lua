-- Servicio y main.lua con dobles de KOReader: sincronización de principio a
-- fin con un plugin oficial falso, offline, registro en Bookshelf y menú.
local F = require("fixtures")

local env

local function stubs(opts)
    opts = opts or {}
    env = {
        connected = opts.connected ~= false,
        shown = {},
        changed = {},
        sidecars = opts.sidecars or {},
        settings = F.memorySettings(),
        server = F.fakeServer({ honor_ids_with_scope = false }),
        logged_in = opts.logged_in ~= false,
        subprocess_runs = 0,
    }
    local P = package.loaded
    P["logger"] = { warn = function() end, info = function() end, dbg = function() end }
    P["ui/uimanager"] = {
        scheduleIn = function(_, _, fn) fn() end,
        nextTick = function(_, fn) fn() end,
        show = function(_, w) env.shown[#env.shown + 1] = w end,
        close = function() end,
    }
    P["datastorage"] = { getSettingsDir = function() return "/tmp/settings" end }
    P["luasettings"] = { open = function(_, path)
        env.settings_path = path
        return env.settings
    end }
    P["ui/network/manager"] = {
        isConnected = function() return env.connected end,
        runWhenOnline = function(_, cb) if env.connected then cb() end end,
    }
    P["ui/trapper"] = { wrap = function(_, fn) return fn() end }
    P["libs/libkoreader-lfs"] = { attributes = function(path, what)
        if what == "modification" then return env.sidecars[path] and env.sidecars[path].mtime end
        if what == "mode" then return "file" end
    end }
    P["docsettings"] = {
        findSidecarFile = function(_, path)
            for sc, data in pairs(env.sidecars) do if data.doc == path then return sc end end
        end,
        open = function(_, path)
            for _, data in pairs(env.sidecars) do
                if data.doc == path then
                    env.sidecar_opens = (env.sidecar_opens or 0) + 1
                    return { readSetting = function(_, k) return data.values[k] end }
                end
            end
        end,
    }
    P["bookorbit_state_manager"] = { onDeviceMaps = function() return { byBookId = F.by_book_id } end }
    local client = {}
    function client:catalogSection(name) return F.scopes_body end
    function client:catalogBooks(params) return env.server.books(params) end
    function client:runInSubprocess(fn)
        env.subprocess_runs = env.subprocess_runs + 1
        local ok, body, err = pcall(fn)
        if not ok then return true, { err = body } end
        return true, { body = body, err = err }
    end
    env.plugin = {
        newClient = function() return client end,
        isLoggedIn = function() return env.logged_in end,
    }
    P["pluginloader"] = { getPluginInstance = function(_, name) if name == "bookorbit" then return env.plugin end end }
    P["bookinfomanager"] = { getBookInfo = function(_, path, cover)
        return { cover_bb = cover and ("bb:" .. path) or nil, cover_w = 300, cover_h = 450 }
    end }
    P["ui/widget/infomessage"] = { new = function(_, o) return o end }
    P["ui/widget/container/widgetcontainer"] = { extend = function(_, cls)
        cls.__index = cls
        function cls:new(o) o = setmetatable(o or {}, cls); if o.init then o:init() end; return o end
        return cls
    end }
    P["ui/widget/menu"] = { new = function(_, o) env.menu = o; return o end }
    P["ui/widget/inputdialog"] = { new = function(_, o)
        env.dialog = o
        o.text = o.input
        function o:getInputText() return self.text end
        function o:onShowKeyboard() end
        return o
    end }
    P["device"] = { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end } }
    -- Módulos del plugin, cargados de nuevo para empezar con estado limpio.
    for _, m in ipairs({ "bscopes_service", "bscopes_source", "bscopes_store", "bscopes_sync", "main" }) do
        P[m] = nil
    end
end

local function fakeBookshelf()
    local bs = { SOURCE_API = 1, specs = {} }
    function bs:registerSource(id, spec) self.specs[id] = spec; return true end
    function bs:sourceChanged(id) env.changed[#env.changed + 1] = id end
    return bs
end

local function newPlugin(ui)
    local Main = dofile("main.lua")
    return Main:new{ ui = ui }
end

T.test("main registra la fuente en Bookshelf y el menú", function()
    stubs()
    local registered_menu
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function(_, p) registered_menu = p end } }
    local plugin = newPlugin(ui)
    T.ok(ui.bookshelf.specs["bookorbit_scope"], "fuente registrada")
    T.eq(registered_menu, plugin)
    local items = {}
    plugin:addToMainMenu(items)
    T.eq(items.bookorbit_scopes.text, "Estanterías BookOrbit")
    T.eq(#items.bookorbit_scopes.sub_item_table, 2)
    T.eq(env.settings_path, "/tmp/settings/bookorbit_scopes.lua")
end)

T.test("Bookshelf aún no cargado: reintenta en el siguiente tick", function()
    stubs()
    local ui = { menu = { registerToMainMenu = function() end } }
    local P = package.loaded
    local ticks = {}
    P["ui/uimanager"].nextTick = function(_, fn) ticks[#ticks + 1] = fn end
    newPlugin(ui)
    ui.bookshelf = fakeBookshelf()   -- Bookshelf termina de cargar
    for _, fn in ipairs(ticks) do fn() end
    T.ok(ui.bookshelf.specs["bookorbit_scope"])
end)

T.test("elegir scope + sync: la estantería se llena y Bookshelf se entera", function()
    stubs()
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui)
    local spec = ui.bookshelf.specs["bookorbit_scope"]
    -- Primera vez: no hay lista de scopes; se descarga (hay red) y se elige.
    local draft = { source = { kind = "bookorbit_scope" } }
    local accepted
    spec.pick(draft, function(v) accepted = (v ~= false) end)
    T.ok(env.menu, "se muestra el menú de scopes")
    T.eq(#env.menu.item_table, 4)
    env.menu.item_table[2].callback()   -- Fantasía
    env.menu.close_callback()
    T.ok(env.dialog, "pide el nombre")
    T.eq(env.dialog.title, "Nombre de la estantería")
    T.eq(env.dialog.input, "Fantasía")
    env.dialog.text = "Fanta"
    env.dialog.buttons[1][2].callback()   -- Guardar
    T.eq(accepted, true)
    T.eq(draft.label, "Fanta")
    T.eq(draft.source.scope_id, "6")
    -- El pick lanza otra sync con la scope ya apuntada.
    local recs = spec.list(draft.source)
    local ids = {}
    for _, r in ipairs(recs) do ids[#ids + 1] = r.bookorbit_id end
    table.sort(ids)
    T.same(ids, { 690, 703, 725 })
    T.ok(#env.changed >= 1, "sourceChanged avisado")
    T.eq(env.changed[1], "bookorbit_scope")
end)

T.test("offline: se pinta la última sincronización sin pedir nada", function()
    stubs()
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui)
    local spec = ui.bookshelf.specs["bookorbit_scope"]
    spec.list({ scope_id = "6" })            -- apunta la scope y sincroniza (hay red)
    local calls_before = #env.server.calls
    env.connected = false
    local recs = spec.list({ scope_id = "6" })
    T.eq(#recs, 3)
    T.eq(#env.server.calls, calls_before, "sin peticiones offline")
    local refreshed = false
    spec.refresh({ scope_id = "6" }, nil, function() refreshed = true end)
    T.ok(refreshed, "deslizar sin red termina igualmente")
    T.ok(env.shown[#env.shown].text:find("Sin conexión"), "avisa de que no hay red")
end)

T.test("progreso local desde el sidecar (cacheado por fecha)", function()
    stubs({ sidecars = {
        ["/mnt/us/documents/Libros/El retorno del rey.sdr/metadata.epub.lua"] = {
            doc = "/mnt/us/documents/Libros/El retorno del rey.epub", mtime = 10,
            values = { percent_finished = 0.45, summary = { status = "reading" } },
        },
    } })
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui)
    local spec = ui.bookshelf.specs["bookorbit_scope"]
    spec.list({ scope_id = "6" })
    local recs = spec.list({ scope_id = "6" })
    for _, r in ipairs(recs) do
        if r.bookorbit_id == 725 then T.near(r.book_pct, 0.45, 1e-9, "Kindle 45% > servidor 1%") end
    end
    T.eq(env.sidecar_opens, 1, "el sidecar solo se abre una vez")
end)

T.test("sin sesión en BookOrbit Sync: fuente no disponible y sin peticiones", function()
    stubs({ logged_in = false })
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui)
    local spec = ui.bookshelf.specs["bookorbit_scope"]
    T.eq(spec.available(), false)
    spec.list({ scope_id = "6" })
    T.eq(#env.server.calls, 0)
end)

T.test("al conectar el wifi sincroniza, pero no dos veces seguidas", function()
    stubs()
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    local plugin = newPlugin(ui)
    plugin:onNetworkConnected()
    T.eq(env.subprocess_runs, 1)
    plugin:onNetworkConnected()
    T.eq(env.subprocess_runs, 1, "dentro de los 15 minutos no repite")
end)

T.test("menú Estado describe las estanterías", function()
    stubs()
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    local plugin = newPlugin(ui)
    ui.bookshelf.specs["bookorbit_scope"].list({ scope_id = "6" })
    local text = plugin:statusText()
    T.ok(text:find("Fantasía: 3 libros"), text)
    T.ok(text:find("Libros del Kindle emparejados: 6"), text)
end)

T.test("portada desde Cover browser", function()
    stubs()
    local Service = require("bscopes_service")
    local bb, w, h = Service.cover("/mnt/us/a.epub")
    T.eq(bb, "bb:/mnt/us/a.epub"); T.eq(w, 300); T.eq(h, 450)
end)

T.test("al registrarse avisa a Bookshelf para repintar la estantería abierta", function()
    stubs()
    local ui = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui)
    T.eq(env.changed[1], "bookorbit_scope")
end)

T.test("arranque real: estantería abierta antes del registro se repinta con libros", function()
    local dir = os.getenv("BOOKSHELF_DIR")
    if not dir then return end
    stubs()
    -- Primera sesión: sincroniza y deja la caché en disco (env.settings).
    local ui1 = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui1)
    ui1.bookshelf.specs["bookorbit_scope"].list({ scope_id = "6" })
    local saved = env.settings
    -- Reinicio de KOReader: sin red, misma caché, registro REAL de Bookshelf.
    stubs({ connected = false })
    env.settings = saved
    local Sources = dofile(dir .. "/lib/bookshelf_sources.lua")
    local shelf = { kind = "bookorbit_scope", scope_id = "6" }
    local shown = Sources.list("bookorbit_scope", shelf)   -- Bookshelf pinta antes del registro
    T.eq(shown, nil, "sin fuente registrada la estantería sale vacía")
    Sources.onChanged("widget", function(id)              -- lo que hace BookshelfWidget:init
        if id == "bookorbit_scope" then shown = Sources.list("bookorbit_scope", shelf) end
    end)
    local bs = { SOURCE_API = Sources.API }
    function bs:registerSource(id, spec) return Sources.register(id, spec) end
    function bs:sourceChanged(id) Sources.changed(id) end
    local ui2 = { menu = { registerToMainMenu = function() end } }
    local ticks = {}
    package.loaded["ui/uimanager"].nextTick = function(_, fn) ticks[#ticks + 1] = fn end
    newPlugin(ui2)
    ui2.bookshelf = bs                                     -- Bookshelf termina de cargar
    for _, fn in ipairs(ticks) do fn() end
    T.ok(shown, "Bookshelf ha vuelto a pedir los libros")
    T.eq(#shown, 3, "y ahora salen los de la caché, sin red")
end)

T.test("Bookshelf que tarda en cargar: reintenta a los 1 y 3 segundos", function()
    stubs()
    local delays = {}
    local pending = {}
    local U = package.loaded["ui/uimanager"]
    U.nextTick = function(_, fn) pending[#pending + 1] = fn end
    U.scheduleIn = function(_, d, fn) delays[#delays + 1] = d; pending[#pending + 1] = fn end
    local ui = { menu = { registerToMainMenu = function() end } }
    newPlugin(ui)
    table.remove(pending, 1)()          -- nextTick: aún no hay Bookshelf
    table.remove(pending, 1)()          -- +1 s: tampoco
    ui.bookshelf = fakeBookshelf()
    table.remove(pending, 1)()          -- +3 s: ya está
    T.same(delays, { 1, 3 })
    T.ok(ui.bookshelf.specs["bookorbit_scope"])
end)

T.test("arranque real (orden de FileManager): la fuente existe antes del primer Show", function()
    local dir = os.getenv("BOOKSHELF_DIR")
    if not dir then return end
    stubs()
    local ui1 = { bookshelf = fakeBookshelf(), menu = { registerToMainMenu = function() end } }
    newPlugin(ui1)
    ui1.bookshelf.specs["bookorbit_scope"].list({ scope_id = "6" })   -- caché en disco
    local saved = env.settings
    stubs({ connected = false })
    env.settings = saved
    local ticks = {}
    package.loaded["ui/uimanager"].nextTick = function(_, fn) ticks[#ticks + 1] = fn end
    package.loaded["ui/uimanager"].scheduleIn = function(_, _, fn) ticks[#ticks + 1] = fn end
    local Sources = dofile(dir .. "/lib/bookshelf_sources.lua")
    -- FileManager:init: plugins en orden alfabético (este antes que Bookshelf),
    -- luego los postInitCallback, luego UIManager:show -> evento Show.
    local post = {}
    local ui = { menu = { registerToMainMenu = function() end } }
    function ui:registerPostInitCallback(cb) post[#post + 1] = cb end
    local plugin = newPlugin(ui)
    local bs = { SOURCE_API = Sources.API }
    function bs:registerSource(id, spec) return Sources.register(id, spec) end
    function bs:sourceChanged(id) Sources.changed(id) end
    ui.bookshelf = bs                                  -- Bookshelf:init
    for _, cb in ipairs(post) do cb() end              -- postInitCallback
    T.eq(plugin:onShow(), nil, "onShow no corta el evento")
    -- Bookshelf:onShow crea la pantalla y pide la estantería (sin ticks).
    local first = Sources.list("bookorbit_scope", { kind = "bookorbit_scope", scope_id = "6" })
    T.ok(first, "la fuente ya está registrada en la primera pintura")
    T.eq(#first, 3)
    T.eq(#ticks, 1, "solo queda el reintento de respaldo, que no hace nada")
    ticks[1]()
end)
