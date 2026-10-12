-- bscopes_i18n.lua -- textos del plugin: inglés por defecto, español si
-- KOReader está en español (mismo criterio que Bookshelf: el ajuste
-- "language" de KOReader y, si no hay, LANG). Lo que no está aquí se pasa al
-- gettext de KOReader (p. ej. "Cancel", "Save").
--
-- Para añadir un idioma: una tabla más en TRANSLATIONS con la misma clave
-- inglesa que usa el código.

local TRANSLATIONS = {
    es = {
        ["BookOrbit shelves"] = "Estanterías BookOrbit",
        ["Bookshelf shelves backed by BookOrbit SmartScopes. Each shows only the books on this device that belong to the chosen SmartScope, with the higher of the device and server progress. Works offline with the last sync. Requires Bookshelf, Cover browser and the BookOrbit Sync plugin."] =
            "Estanterías de Bookshelf asociadas a una SmartScope de BookOrbit. Cada una muestra solo los libros de este dispositivo que pertenecen a la SmartScope elegida, con el progreso más alto entre el dispositivo y el servidor. Funciona sin conexión con la última sincronización. Requiere Bookshelf, Cover browser y el plugin BookOrbit Sync.",
        ["BookOrbit SmartScope"] = "SmartScope de BookOrbit",
        ["Choose a SmartScope"] = "Elige una SmartScope",
        ["Shelf name"] = "Nombre de la estantería",
        ["No saved SmartScope list. Connect to Wi-Fi once and try again."] =
            "No hay lista de SmartScopes guardada. Conecta el wifi una vez y vuelve a intentarlo.",
        ["Sync now"] = "Sincronizar ahora",
        ["Status"] = "Estado",
        ["Syncing shelves…"] = "Sincronizando estanterías…",
        ["Shelves updated."] = "Estanterías actualizadas.",
        ["Offline: showing the last sync."] = "Sin conexión: se muestra la última sincronización.",
        ["The BookOrbit Sync plugin is not enabled or not logged in."] =
            "El plugin BookOrbit Sync no está activo o no tiene sesión iniciada.",
        ["Could not create the BookOrbit client."] = "No se pudo crear el cliente de BookOrbit.",
        ["Sync cancelled."] = "Sincronización cancelada.",
        ["Already up to date."] = "Ya estaba sincronizado.",
        ["BookOrbit rejected the credentials (check BookOrbit Sync)."] =
            "BookOrbit rechaza las credenciales (revisa BookOrbit Sync).",
        ["Sync error: %1"] = "Error al sincronizar: %1",
        ["never"] = "nunca",
        ["Last sync: %1"] = "Última sincronización: %1",
        ["Matched books on this device: %1"] = "Libros emparejados en este dispositivo: %1",
        ["SmartScopes in the list: %1"] = "SmartScopes en la lista: %1",
        ["Shelves:"] = "Estanterías:",
        ["%1: %2 books"] = "%1: %2 libros",
        [" (incomplete: SmartScope too large)"] = " (incompleta: SmartScope demasiado grande)",
        ["scope %1"] = "scope %1",
        ["Last error: %1"] = "Último error: %1",
        ["Bookshelf is not active."] = "Bookshelf no está activo.",
        ["BookOrbit SmartScopes"] = "SmartScopes de BookOrbit",
        ["BookOrbit SmartScopes (stack)"] = "SmartScopes de BookOrbit (pila)",
        ["SmartScopes: all"] = "SmartScopes: todas",
        ["SmartScopes: %1 selected"] = "SmartScopes: %1 elegidas",
        ["%1 (%2)"] = "%1 (%2)",
        ["SmartScopes on this shelf"] = "SmartScopes de esta estantería",
        ["All SmartScopes"] = "Todas las SmartScopes",
        ["Choose SmartScopes…"] = "Elegir SmartScopes…",
        ["Choose SmartScopes"] = "Elige las SmartScopes",
        ["OK (%1 selected)"] = "Aceptar (%1 elegidas)",
        ["Choose at least one SmartScope."] = "Elige al menos una SmartScope.",
    },
}

local M = {}

local function detectLang()
    local lang = G_reader_settings and G_reader_settings.readSetting
        and G_reader_settings:readSetting("language")
    if type(lang) == "string" and lang ~= "" then return lang end
    local lc = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    return lc:match("^([a-zA-Z_]+)") or "en"
end

local function tableFor(lang)
    if type(lang) ~= "string" then return nil end
    return TRANSLATIONS[lang] or TRANSLATIONS[lang:match("^([a-zA-Z]+)") or ""]
end

local current

function M.setLanguage(lang)
    current = tableFor(lang)
end

function M.gettext(msgid)
    if current == nil then current = tableFor(detectLang()) or false end
    local t = current and current[msgid]
    if t then return t end
    local ok, ko = pcall(require, "gettext")
    if ok and type(ko) == "function" then return ko(msgid) end
    if ok and type(ko) == "table" then
        local mt = getmetatable(ko)
        if mt and mt.__call then return ko(msgid) end
    end
    return msgid
end

-- "%1", "%2"… como util.template de KOReader.
function M.template(fmt, ...)
    local args = { ... }
    return (fmt:gsub("%%(%d)", function(i)
        local v = args[tonumber(i)]
        return v ~= nil and tostring(v) or ""
    end))
end

-- Todas las traducciones de una clave (para reconocer nombres automáticos).
function M.allForms(msgid)
    local out = { msgid }
    for _, t in pairs(TRANSLATIONS) do
        if t[msgid] then out[#out + 1] = t[msgid] end
    end
    return out
end

M._TRANSLATIONS = TRANSLATIONS
return M
