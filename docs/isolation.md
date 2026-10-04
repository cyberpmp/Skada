# Skada's isolation from other addons

Skada keeps to its own UI surfaces. This page is the complete inventory of
every place Skada could touch anything outside itself, why each one exists,
and what bounds its blast radius. If another addon misbehaves while Skada is
loaded, this is the checklist to work through.

## What Skada never touches

- **No hooked secure functions, no hooked scripts.** Skada calls
  `hooksecurefunc` never and `Frame:HookScript` never (it chains its own
  scripts through `SkadaCompat.AppendScript` instead). Any future `HookScript`
  is blocked by the test-harness lint.
- **No frames made or owned by other addons** — other than the two shared
  Blizzard frames listed below (color picker; now nothing else).
- **No chat filters, no chat channel joins, no macros**, and no combat-log
  parsing that consumes messages other addons also read. Skada reads event
  data on its own event frame and passes it around internally.
- **No other addon's SavedVariables**, no global function Skada defines for
  itself that shadows a Blizzard API.

## Skada's own surfaces (nothing shared)

- **Tooltips** — Skada renders every tooltip (meter rows, window header,
  report and settings buttons) on its own `GameTooltip` frame named
  `SkadaTooltip` (`Skada.Common.GetTooltip()`). It never calls `SetOwner`,
  `AddLine`, `Show` or `Hide` on the Blizzard-shared `GameTooltip`, which
  other UIs need — the transmogrify service, for example, feeds item
  hyperlinks into the shared tooltip (`SetHyperlink`) to make the server
  fetch item data, and builds its per-slot available-item lists from what
  lands in the client's item cache. An owning or hiding call from Skada
  during such a fetch swallows the data, which used to show up as some
  transmog slots listing nothing while a meter tooltip was on screen.
  The `isolation` test suite instruments the shared `GameTooltip` and
  asserts zero traffic from Skada across boot, repaints and hover paths.
- **Windows, rows, fonts, menus** — every frame Skada creates is named
  `Skada*` and scripted on Skada's own tables.
- **Settings** — one namespace (`SkadaDB`), loaded first via
  `LoadSavedVariablesFirst`, saved and read back only by Skada code.
- **Addon-message traffic** — only Skada's threat module sends anything
  (a rate-limited live-threat query, 1 every 0.5 s in combat at most, with
  a 15 s backoff after 8 unanswered queries), and it reads only its own
  `CHAT_MSG_ADDON` prefixes. It never sends while you are not in combat
  targeting a live enemy, so browsing menus, the bank or the transmog
  service sends nothing.
- **Combat-log data from Nampower** — read-only access to the debug-log
  APIs Nampower exposes; never written.

## Shared Blizzard frames Skada still touches, and why

Only one shared frame remains, and it is repaired, not restyled:

- **`ColorPickerFrame`** (Blizzard's shared color picker). Skada appends an
  `OnShow`/`OnHide` script that re-layers the frame (`ApplyStrata`,
  `FixLevels`) so its own settings dialog shows the picker above it. This
  fixes a vanilla-client bug where the picker or its children load at a
  strata below dialogs; every addon that opens the picker benefits. Skada
  never blocks clicks or swallows the picker's Okay/Cancel.

## Global functions Skada installs for the whole client

These live in `core/core.compat.lua` and exist because this vanilla 1.12.1
client (Nampower/ClassicAPI build) ships a Lua runtime with real bugs.
Guarded shims only define a function when the client lacks a working one;
unguarded shims replace a broken native and apply to everything loaded
after Skada. `libs/` third-party code is excluded from our linting but is
self-contained.

### Unguarded (replace the native everywhere)

| Override | Why the native is broken | Bounds |
| --- | --- | --- |
| `string.split` + `strsplit` | The native `string.split` feeds `table.concat` non-strings ("table contains non-strings") for some inputs. The replacement follows the standard split contract: delimiters are matched literally one character at a time, empty fields are kept (`"a::b"` → `"a"`, `""`, `"b"`), non-string values are read as text, and the optional `pieces` argument caps the field count with the remainder in the final field. | Skada itself never calls it. It exists for other addon code, which is why it must be contract-correct rather than merely good enough for Skada. |
| `table.getn/setn/insert/remove/sort/concat`, `foreachi`, `unpack` | The client is built with `LUA_COMPAT_GETN` plus a side-tracked table length: `#`, `getn` and everything built on them (sorting a dense table, `tremove` without index) miscount once a table's slot `n` drifts from its real content — items silently vanish, blank entries appear, sorts no-op. The shims re-scan real content (`realgetn`) instead of trusting the tag. | Fixes real breakage in other addons (Bagshui's blank pages, FuBar-style plugins). Scoping them away would mean rewriting every module Skada ships; the semantics match what the addon authors' code was written for. |

### Guarded (only used where the client lacks a working one)

| Override | Purpose |
| --- | --- |
| `string.match` rewrite | A `probe`-guarded replacement that fixes range-order blind matching (`"[A%-Z]"` style classes); re-probed each call so a later addon that replaces it again (RollFor's backport) wins cleanly. |
| `strmatch`, `strtrim`, `wipe`, `floor/ceil/max/min`, `loadstring` | Standard polyfills, defined only if missing. |
| `ChatEdit_InsertLink` | No-op stub so code that calls it while no object exists does not error the dispatcher. |

### Scoped to Skada's own frames

| Override | Behaviour |
| --- | --- |
| `CreateFrame` wrapper | Wraps the native and adds per-frame fixes, but only for frames Skada or its vendored widgets create or template with `OptionsListButtonTemplate`: width/height wrappers remember explicitly-set sizes across scale quirks, a `SetParent` layering shim re-derives strata where the client loses it, and the `OptionsListButtonTemplate` bypass hand-builds rows the client cannot. Frames created by other addons keep native behaviour except the template bypass on the one broken template. |

## If another addon misbehaves while Skada is loaded

1. **Check whether the symptom exists with Skada removed** (rename the
   `Skada` folder) rather than disabled — load order only matters for
   Skada's *global shims*, and they are the only shared surface.
2. If it reproduces, check the addon's code against the tables above —
   especially whether it binds a shimmed global into a local upvalue at
   load time (Skada must load first in the `.toc` order for another addon
   to receive these: alphabetical order puts Skada ahead of most names).
3. Report the exact failing call. Every shim above is small enough to
   carve out per-consumer if a real conflict shows up.