local I18n = require("bscopes_i18n")

T.test("inglés por defecto con KOReader en inglés", function()
    I18n.setLanguage("en")
    T.eq(I18n.gettext("BookOrbit shelves"), "BookOrbit shelves")
    T.eq(I18n.gettext("BookOrbit SmartScope"), "BookOrbit SmartScope")
    I18n.setLanguage("es")
end)

T.test("español con KOReader en español (también es_ES)", function()
    I18n.setLanguage("es_ES")
    T.eq(I18n.gettext("BookOrbit shelves"), "Estanterías BookOrbit")
    I18n.setLanguage("es")
    T.eq(I18n.gettext("Shelf name"), "Nombre de la estantería")
end)

T.test("plantillas %1 %2", function()
    T.eq(I18n.template("%1: %2 books", "Fantasy", 3), "Fantasy: 3 books")
end)

T.test("todas las claves españolas existen en el código", function()
    local code = ""
    for _, f in ipairs({ "main.lua", "bscopes_source.lua", "bscopes_stack.lua", "_meta.lua" }) do
        code = code .. io.open(f):read("*a")
    end
    for key in pairs(I18n._TRANSLATIONS.es) do
        local plain = key:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
        T.ok(code:find('"' .. plain .. '"'), "clave sin uso: " .. key)
    end
end)

T.test("todos los textos visibles del código tienen traducción", function()
    local missing = {}
    for _, f in ipairs({ "main.lua", "bscopes_source.lua", "bscopes_stack.lua", "_meta.lua" }) do
        local src = io.open(f):read("*a")
        for key in src:gmatch('_%("([^"]+)"%)') do
            if key ~= "Cancel" and key ~= "Save" and not I18n._TRANSLATIONS.es[key] then
                missing[#missing + 1] = key
            end
        end
    end
    -- ERRORS se traduce con _(ERRORS[err]): comprobar sus valores también.
    local main = io.open("main.lua"):read("*a")
    local block = main:match("local ERRORS = (%b{})")
    for key in block:gmatch('= "([^"]+)"') do
        if not I18n._TRANSLATIONS.es[key] then missing[#missing + 1] = key end
    end
    T.eq(#missing, 0, table.concat(missing, " | "))
end)

T.test("en inglés la fuente y el menú salen en inglés", function()
    I18n.setLanguage("en")
    package.loaded["bscopes_source"] = nil
    local Source = require("bscopes_source")
    local Store = require("bscopes_store")
    local F = require("fixtures")
    local spec = Source.spec{ store = Store.new(F.memorySettings()), available = function() return true end,
        chooseScope = function() end, ensureScopes = function(cb) cb(false) end, notify = function() end }
    T.eq(spec.label(), "BookOrbit SmartScope")
    I18n.setLanguage("es")
    package.loaded["bscopes_source"] = nil
end)

T.test("_meta.lua se lee aunque el módulo de idiomas no esté a mano (App Store)", function()
    local saved_path, saved_mod = package.path, package.loaded["bscopes_i18n"]
    package.path = "/nonexistent/?.lua"
    package.loaded["bscopes_i18n"] = nil
    local ok, meta = pcall(dofile, "_meta.lua")
    package.path, package.loaded["bscopes_i18n"] = saved_path, saved_mod
    T.ok(ok, tostring(meta))
    T.eq(type(meta), "table")
    T.eq(meta.fullname, "BookOrbit shelves", "sin el módulo, en inglés")
    T.ok(meta.version:match("^%d+%.%d+%.%d+$"))
end)

T.test("_meta.lua en KOReader en español", function()
    I18n.setLanguage("es")
    local meta = dofile("_meta.lua")
    T.eq(meta.fullname, "Estanterías BookOrbit")
end)

T.test("App Store saca la versión del _meta.lua y no confunde fullname con name", function()
    local src = io.open("_meta.lua"):read("*a")
    -- Mismas expresiones que appstore.koplugin (detectPluginFromArchive).
    T.eq(src:match('name%s*=%s*["\']([^"\']+)["\']'), nil)
    T.eq(src:match('version%s*=%s*["\']([^"\']+)["\']'), dofile("_meta.lua").version)
end)
