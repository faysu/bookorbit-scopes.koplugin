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
