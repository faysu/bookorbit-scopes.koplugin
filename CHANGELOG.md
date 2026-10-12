# Changelog

## 0.1.2 — 2026-10-12

- **Fix: SmartScope shelf empty after starting KOReader.** If Bookshelf reopened a SmartScope shelf at startup, it showed no books until you visited another shelf (and, in Spines view, waited 30 seconds). This plugin loads before Bookshelf, and Bookshelf builds its screen on the first `Show` event, before the plugin had registered its source; in Spines view Bookshelf then kept the empty list cached for 30 seconds. The source is now registered in the UI's post-init callback, after every plugin has started and before anything is shown, so the first paint already has the books (offline too). `onShow`, a `sourceChanged` nudge and retries after 1 and 3 seconds remain as fallbacks.

## 0.1.1 — 2026-10-12

- **Shelf name when picking a SmartScope.** After choosing the scope you are asked for the shelf name, prefilled with the scope title, so long titles can be shortened. Cancel keeps the scope title.
- **Names you typed are kept.** Picking another scope no longer overwrites a custom shelf name; only automatic names (Bookshelf's "New shelf" or a previous scope title) are replaced.
- **Clean copies from macOS.** New `tools/instalar_kindle.sh` (install over USB) and `tools/empaquetar.sh` (release zip) copy without the hidden `._*` files macOS writes on FAT disks; Bookshelf tried to load the ones in its `micromodules` folder.

## 0.1.0 — 2026-10-12

First release.

- New Bookshelf shelf source **SmartScope de BookOrbit** (Bookshelf Source API v1, `list` mode).
- A shelf shows only the books on the device that belong to the chosen BookOrbit SmartScope. Books are matched through BookOrbit Sync's hash links; no title or ISBN guessing.
- Progress is the higher of the server's (reading on other devices) and the device's own sidecar; a book is finished if either side says so.
- Works offline from the last sync (`koreader/settings/bookorbit_scopes.lua`). Syncs on Wi-Fi connect, on pull-down, when a scope is picked, from the menu, and when a shelf is shown with Wi-Fi on and the last sync is older than 6 hours.
- Read-only: only `GET` requests; never writes progress, statuses or sidecars. Opening a book is unchanged (BookOrbit Sync still asks server vs local position).
- **Tools → Estanterías BookOrbit**: *Sincronizar ahora* and *Estado*.
- Known limitation: BookOrbit 3.3.0 ignores `ids` together with `smartScopeId` ([bookorbit/bookorbit#1774](https://github.com/bookorbit/bookorbit/issues/1774)), so each SmartScope is paged through and intersected locally, capped at 6,000 books per scope.
