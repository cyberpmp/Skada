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
- **No shared library or API global, replaced or added.** The table
  library, `unpack`, `string.*` and `CreateFrame` are exactly what the
  client (and any addon loaded before Skada) left there. Skada's fixes for
  this client live on `SkadaCompat` and its own files take them as locals.
  The `boot` suite snapshots every shared library member and API global
  before Skada loads and fails if one changed; a harness lint fails any
  Skada file that calls the shared table library directly.
- **No client settings.** Skada writes no CVar. On Nampower 4.5 and later,
  registering for an event is what turns it on; an older build is used
  only if its event CVars are already on, and otherwise Skada stays on
  chat text.

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
- **Combat events from Nampower** — read on Skada's own event frame; no
  Nampower setting is ever written.

## Shared state Skada still touches, and why

- **`ColorPickerFrame`** (Blizzard's shared color picker), only while Skada
  itself has it open. On this client a raised frame's strata and level
  never reach its children, so the Okay and Cancel buttons would stay
  under the picker's backdrop and every click on them would be swallowed.
  When Skada's color control opens the picker it records the picker's
  strata and level; an appended `OnShow`/`OnHide` re-layers the children
  while Skada owns it and puts strata, level and the toplevel flag back
  when it closes. Opened by anything else, those scripts do nothing.
- **`UISpecialFrames`** — Skada's settings dialog and report popup add
  their names so Escape closes them, through the client's own `tinsert`.

## Skada's private compatibility layer

`core/core.compat.lua` exists because this 1.12.1 client's Lua has real
gaps. Everything in it is reachable only through `SkadaCompat`:

| Member | Why |
| --- | --- |
| `SkadaCompat.Table` (`getn`, `setn`, `insert`, `remove`, `sort`, `concat`) | The client tracks an array's length as a side fact that goes stale when a table is written directly; the native `sort` and `concat` read that stale count (seen in game as scrambled damage windows). The private library derives every length from the table's contents, never reads through `__index`, and takes fixed parameters (every `...` call allocates on this client). |
| `SkadaCompat.Match` | RollFor replaces the global `string.match` with a captures-only version. Skada probes whatever is installed and keeps it only if it passes; otherwise it matches through `string.find`. The global is left as RollFor left it. |
| `SkadaCompat.CreateFrame` | Skada's own frames: `GetWidth`/`GetHeight` answer with the explicit size while the client's rect still reads 0 before the first render. |
| `SkadaCompat.ApplyStrata`, `FixLevels`, `AppendScript` | Layering and script-chaining helpers for Skada's own frames (the client's `HookScript` drops the original handler's arguments). |

## If another addon misbehaves while Skada is loaded

1. **Check whether the symptom exists with Skada disabled.** Skada changes
   no shared function, so a difference points at the two shared items
   above or at load-time cost, not at altered library behaviour.
2. Report the exact failing call along with the addon list.
