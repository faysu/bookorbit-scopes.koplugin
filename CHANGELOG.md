# Changelog

## 0.2.0 — 2026-10-12

- **New: SmartScope stack shelves.** A second shelf source, **BookOrbit SmartScopes (stack)**, shows your SmartScopes as folders, like Bookshelf's Genres shelf. Each folder is titled with the SmartScope's name and how many of its books are on the device (e.g. "Fantasy (5)"), and uses one of those books' covers. Open a folder to see its books, sorted by title, with the same progress as a single-SmartScope shelf.
  - **All SmartScopes or a hand-picked set.** When adding the shelf, choose *All SmartScopes* or *Choose SmartScopes…* and tick the ones you want. Change it later from the shelf editor (*SmartScopes: all* / *SmartScopes: N selected*).
  - With *All SmartScopes*, SmartScopes with no books on the device are hidden; hand-picked ones are always shown.
  - Works offline from the last sync. The first time, every SmartScope in the list is synced (one pass per SmartScope; see the known limitation in the README for very large libraries).
- **English UI.** The plugin now follows KOReader's language: English by default, Spanish when KOReader is set to Spanish (same rule Bookshelf uses). The single-SmartScope source is **BookOrbit SmartScope** and the menu **Tools → BookOrbit shelves** (*Sync now*, *Status*). Shelves you already have keep working; only labels change.
- **Device-neutral wording.** Texts say "this device" instead of "Kindle"; nothing in the plugin is Kindle-specific.
- README fully in English, using the exact menu names from KOReader, Bookshelf and BookOrbit Sync.

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
