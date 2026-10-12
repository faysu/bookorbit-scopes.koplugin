# BookOrbit SmartScope shelves for Bookshelf (KOReader)

`bookorbit-scopes.koplugin` adds a new shelf source to [Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin): **BookOrbit SmartScope**. A shelf using it shows **only the books that are on your device** and belong to a [BookOrbit](https://github.com/bookorbit/bookorbit) SmartScope you pick. For progress it shows **the higher of the device and the server**, so reading done on other devices counts. It works **offline** with the last sync.

The plugin follows KOReader's language: English by default, Spanish when KOReader is set to Spanish.

> 🇪🇸 **En español:** plugin de KOReader que añade a Bookshelf estanterías asociadas a una SmartScope de BookOrbit. Cada una muestra solo los libros del lector que pertenecen a esa scope, con el progreso más alto entre el lector y el servidor. Funciona sin conexión con la última sincronización. Si KOReader está en español, el plugin también.

## Requirements

- KOReader v2026.07.1 or newer.
- **Bookshelf** v5.4.4 or newer (Source API v1).
- KOReader's **Cover browser** plugin enabled. Bookshelf needs it.
- **BookOrbit Sync**, the official BookOrbit KOReader plugin, installed, logged in and with its automatic sync on. This plugin relies on it for two things:
  - talking to the server, through its credentials and its client;
  - knowing which BookOrbit book each file on the device is (its hash matching).

## What it does

There are two kinds of shelf:
- **BookOrbit SmartScope:** one SmartScope per shelf, showing its books. It works in every Bookshelf view, Spines included.
- **BookOrbit SmartScopes (stack):** several SmartScopes on one shelf, as folders, like Bookshelf's Genres shelf. Each folder shows the SmartScope's name, how many of its books are on the device (e.g. "Fantasy (5)") and one of their covers. Open a folder to see its books. Pick **All SmartScopes** or **Choose SmartScopes…** and tick the ones you want; change it later in the shelf editor. With *All SmartScopes*, SmartScopes with no books on the device are hidden. Bookshelf shows this kind of shelf as a grid or list (it doesn't offer Spines for folder shelves).

Both kinds:

- **Choosing:** when you create or edit a shelf in Bookshelf, tap **Source / grouping** and pick **BookOrbit SmartScope** or **BookOrbit SmartScopes (stack)**. A list of your SmartScopes appears. Then you are asked for a shelf name, prefilled with the scope title so you can shorten it. A name you typed yourself is kept if you change the scope later. You can also rename the shelf any time with Bookshelf's **Edit label**.
- **Which books appear:** books on the device that are matched to BookOrbit and belong to that SmartScope. It does **not** browse your whole BookOrbit library looking for new books; use BookOrbit Sync to download those.
- **Progress:** the higher of the server's progress and the device's own (KOReader sidecar). A book counts as finished if either side says so.
- **Opening a book:** nothing changes. Books open as normal files, and BookOrbit Sync still asks whether to jump to the server position or keep the local one.
- **Read-only:**
  - it never uploads progress or statuses;
  - it never writes to sidecars;
  - it only sends `GET` requests to the catalogue.
- **Offline:** shelves are drawn from the last sync, stored in `koreader/settings/bookorbit_scopes.lua`.

### When it syncs

- When Wi-Fi connects, if the last sync is older than 15 minutes.
- When a shelf is shown, if the last sync is older than 6 hours and Wi-Fi is already on. It never turns Wi-Fi on by itself.
- When you pick a SmartScope for a shelf.
- When you pull down on the shelf, or via **Tools → BookOrbit shelves → Sync now** (the menu entry is at the end of KOReader's Tools menu).

**Status**, in the same menu, shows:
- the last sync;
- how many device books are matched;
- how many books each shelf has;
- the last error, if any.

## Known limitation (BookOrbit 3.3.0)

BookOrbit's KOReader catalogue (`GET /api/v1/koreader/plugin/catalog/books`) **ignores the `ids` filter when it is combined with `smartScopeId`**. Reported upstream: **[bookorbit/bookorbit#1774](https://github.com/bookorbit/bookorbit/issues/1774)**.

Because of that, the plugin **pages through each SmartScope used by a shelf** (every SmartScope, if a stack shelf uses *All SmartScopes*) and intersects it with the books on the device:
- **Small and medium libraries:** fine, about one request per 100 books in the scope.
- **Cap:** it stops at **60 pages (6,000 books) per SmartScope**. Beyond that the shelf may be **incomplete**, and **Status** says so.

If BookOrbit fixes the filter, the plugin notices by itself and switches to requesting only the device's books, 100 at a time. No update is needed.

## Installation

1. Back up `koreader/settings` (and `settings.reader.lua`).
2. Download `bookorbit-scopes.koplugin.zip` from the [latest release](../../releases/latest) and unzip it into `koreader/plugins/`. You should end up with `koreader/plugins/bookorbit-scopes.koplugin/main.lua`.
3. Restart KOReader.
4. In Bookshelf: **Add shelf**, then **Source / grouping → BookOrbit SmartScope**, and pick a SmartScope.

Plugin folders: Kindle `/mnt/us/koreader/plugins/`, Kobo `/mnt/onboard/.adds/koreader/plugins/`, Android `<koreader-dir>/plugins/`.

On a Kindle, KOReader has no USB storage mode: exit KOReader (**Exit**, in the last menu tab) and plug the cable in from the Kindle's own screen.

**Copying from a Mac?** macOS writes hidden `._*` files on FAT disks, and Bookshelf tries to load the ones inside its `micromodules` folder. Copy with `cp -X`, or use `tools/instalar_kindle.sh` from this repository.

### Coming from the BookOrbit dashboard as home screen

If BookOrbit's dashboard used to be your home screen, two settings will fight with Bookshelf:
- **Tools → BookOrbit → Settings → Dashboard → Open dashboard on startup → Off.**
- If you set up a KOReader profile that opens the dashboard when a book closes: **Tools → Profiles → (your profile) → Auto-execute** and untick **on book closing**.

Also set Bookshelf as the start screen: in the file browser's first menu tab, **Start with → Bookshelf**. If Bookshelf doesn't appear at all, check **Tools → More tools → Plugin management**: **Bookshelf**, **Cover browser** and **BookOrbit shelves** must be enabled.

## Devices

The plugin only uses KOReader's own APIs (document settings, Cover browser's cache, network events) plus the Bookshelf Source API and BookOrbit Sync's client. Nothing in it is specific to the Kindle.
- **Tested** on a Kindle Paperwhite 5 (KOReader v2026.07.1, Bookshelf 5.4.4).
- **Kobo, PocketBook and Android:** expected to work wherever Bookshelf and BookOrbit Sync work, but not tested yet. Reports are welcome.

## Development

```sh
brew install luajit        # or your distro's luajit
tests/run.sh               # all suites
tests/run.sh test_logic    # one suite
tools/empaquetar.sh        # builds dist/bookorbit-scopes.koplugin.zip
```

The first time, `tests/run.sh` clones Bookshelf at a pinned commit into `tests/.cache`, so the source is checked against Bookshelf's real registry (`lib/bookshelf_sources.lua`).

There is also a read-only check against a real server. It uses a copy of the device's `settings.reader.lua` and `bookorbit_sync_state.lua`, and never prints credentials:

```sh
luajit tools/probar_servidor.lua path/to/settings.reader.lua path/to/bookorbit_sync_state.lua 6 22
```

| File | Purpose |
|---|---|
| `main.lua` | KOReader glue: Bookshelf registration, menu, Wi-Fi events, scope picker, name dialog. |
| `bscopes_i18n.lua` | UI texts: English, plus Spanish when KOReader is in Spanish. |
| `bscopes_service.lua` | Shared state: cache, background sync, sidecars, covers. |
| `bscopes_source.lua` | The single-SmartScope source (Source API v1, `list` mode). |
| `bscopes_stack.lua` | The SmartScope stack source (Source API v1, `fetch` mode with folders). |
| `bscopes_sync.lua` | One sync pass, run inside BookOrbit Sync's subprocess. |
| `bscopes_store.lua` | Offline cache. |
| `bscopes_logic.lua` | Pure logic: statuses, progress, dates, membership, records. |

## Credits

The sync pattern is adapted from `integrations/sui_bookorbit_want.lua` in [komadorirobin/simpleui.koplugin](https://github.com/komadorirobin/simpleui.koplugin) (MIT, © 2026 doctorhetfield-cmd):
- it uses BookOrbit Sync's client;
- it uses its on-device book map;
- it runs requests in a subprocess.

## License

MIT, see [LICENSE](LICENSE).
