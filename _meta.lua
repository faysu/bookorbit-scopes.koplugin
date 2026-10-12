-- Puede cargarse fuera del plugin (p. ej. App Store lo lee con dofile, sin la
-- carpeta del plugin en package.path): si no se encuentra el módulo de
-- idiomas, los textos quedan en inglés en vez de fallar.
local ok, I18n = pcall(require, "bscopes_i18n")
local _ = (ok and type(I18n) == "table" and I18n.gettext) or function(s) return s end
return {
    version = "0.2.1",
    fullname = _("BookOrbit shelves"),
    description = _("Bookshelf shelves backed by BookOrbit SmartScopes. Each shows only the books on this device that belong to the chosen SmartScope, with the higher of the device and server progress. Works offline with the last sync. Requires Bookshelf, Cover browser and the BookOrbit Sync plugin."),
}
