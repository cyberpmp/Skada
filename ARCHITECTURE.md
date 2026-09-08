# Architecture

This document describes the runtime boundaries and extension contracts for the
OctoWoW Vanilla build of Skada. User-facing installation and controls belong in
[README.md](README.md).

## Runtime constraints

- The target client uses the Vanilla 1.12.1 interface and ClassicAPI.
- `Skada.toc` is the authoritative load order.
- Runtime code avoids Ace, LibStub, and display-framework dependencies.
- Combat data is stored as bounded aggregates, not an event timeline.
- Hot paths favor reusable tables and scalar arguments over per-event objects.

## Repository layout

```text
Skada/
|-- core/       Runtime foundation, defaults, and compatibility
|-- data/       Identity, aggregation, segments, boss detection, and resets
|-- threat/     Server threat provider and local fallback estimator
|-- tracking/   Cast, aura, spell, group, and damage observation
|-- combat/     Nampower event ingest, combat-text parser, and routing
|-- modes/      Meter-mode projections
|-- ui/         Window presentation, rendering, reporting, and docking
|-- options/    Settings schema, dialog and control renderers, and minimap entry point
|-- commands/   Slash-command entry points
|-- media/      Bundled fonts and textures
|-- tests/      Host-side test suite: harness, stubs, and ordered domain suites
`-- Skada.toc   Version metadata and authoritative runtime load order
```

Runtime filenames use a subsystem-qualified convention such as
`data/data.segments.lua` and `options/options.schema.lua`. This keeps file
ownership clear in search results while preserving explicit TOC ordering.

## Module map

| Layer | Modules | Responsibility |
| --- | --- | --- |
| Foundation | `core/core.compat.lua`, `core/core.common.lua`, `core/core.defaults.lua`, `core/core.runtime.lua`, `ui/ui.style.lua` | Client-gap shims and stdlib repairs, compatibility helpers, profile defaults, lifecycle, events, tickers, internal messages, rendering policy, and shared visuals |
| Identity and data | `data/data.identity.lua`, `data/data.aggregator.lua`, `data/data.boss.lua`, `data/data.segments.lua`, `data/data.navigation.lua`, `data/data.lua`, `data/data.reset.lua` | Roster and pet ownership, aggregate mutation, boss recognition, segment lifecycle, history navigation, the data facade, and reset policies |
| Threat | `threat/threat.estimate.lua`, `threat/threat.lua` | Combat-scoped local estimates and the authoritative OctoWoW Threat API v4 provider |
| Enrichment | `tracking/tracking.spells.lua`, `tracking/tracking.casts.lua`, `tracking/tracking.auras.lua`, `tracking/tracking.damage.lua`, `tracking/tracking.group.lua`, `tracking/tracking.lua` | Spell metadata, cast correlation, dispels, interrupts, aura uptime, last-hit evidence, and group observation |
| Parsing and projection | `combat/combat.parser.lua`, `combat/combat.nampower.lua`, `modes/modes.lua` | Combat-text routing, Nampower server-event ingest, and projection of aggregates into meter modes |
| Window UI | `ui/ui.config.lua`, `ui/ui.presenter.lua`, `ui/ui.rows.lua`, `ui/ui.snap.lua`, `ui/ui.report.lua`, `ui/ui.lua` | Per-window persistence, display models, pooled row rendering, snapping, reporting, and window composition |
| Settings and entry points | `options/options.schema.lua`, `options/options.controls.lua`, `options/options.dialog.lua`, `options/options.minimap.lua`, `options/options.lua`, `commands/commands.lua` | Declarative options table, control renderers, the settings dialog itself, minimap access, the settings facade, and slash commands |

Modules loaded later may reference tables created earlier. Event callbacks
resolve cross-module state at call time so initialization remains ordered and
explicit.

## Data flow

0. `combat/combat.nampower.lua` is the authoritative source when Nampower and
   GUID-addressable unit tokens are both present. It reads damage, healing,
   power, avoidance, dispels and deaths from the server's own events and
   suppresses exactly those routes in the parser. See `docs/NAMPOWER.md`.
1. `combat/combat.parser.lua` compiles client combat formats once and routes
   only the chat events on which each format can occur. It stays the only
   source for interrupts, crowd control and aura uptime, and the fallback for
   everything else when the ingest is inactive.
2. Tracking services enrich sparse text with spell IDs, GUIDs, aura sources,
   dispel snapshots, interrupt casts, and last-hit evidence. Ambient aura events
   coalesce into a bounded queue that scans one unit per tracking tick; segment
   start queues only unseen group, target, and focus units instead of
   synchronously enumerating a full roster on the pull path. Combat roster
   changes use the same queue, skipping fresh cached units so their next buff
   applications are not suppressed by a redundant pending baseline.
3. `data/data.lua` normalizes accepted facts and delegates mutations to
   `data/data.aggregator.lua` for both Current and Overall sets.
4. `modes/modes.lua` projects actor and detail fields without mutating the
   sets.
5. `ui/ui.presenter.lua` builds reusable display entries; `ui/ui.rows.lua`
   paints pooled rows and performs easing separately from rebuilds.

Threat follows a separate path. Accepted damage and healing facts are published
to `threat/threat.estimate.lua`, while `threat/threat.lua` requests and parses
live server snapshots. Neither provider writes threat into combat segments.

## Core contracts

### Initialization and events

`core/core.runtime.lua` owns one frame. Components register ordered
initializers, named tickers, client event handlers, and internal subscribers.
Event handlers, ticker callbacks, and internal subscribers are protected
individually so one failure does not prevent unrelated work from running.
Repeated identical ticker errors are reported only once until that ticker
succeeds again.

Internal messages are synchronous and registration-order dependent:

| Message | Publisher | Consumers |
| --- | --- | --- |
| `combatStateChanged(inCombat)` | Segment state machine | Window auto-switching and threat-estimate lifecycle |
| `segmentStarted(segment, now)` | Segment state machine | Queue unseen aura baselines |
| `segmentArchived(data, segment)` | Segment state machine | Numeric history-selection migration |
| `dataReset()` | Data facade | Window view reset and threat-estimate reset |
| `damageRecorded(...)` | Data facade | Local threat estimator |
| `healingRecorded(...)` | Data facade | Local threat estimator |
| `unitDied(identifier)` | Data facade | Local threat cleanup |
| `windowListChanged(ui)` | Window manager | Settings navigation tree |

Internal messages must use `Subscribe` and `Publish`; they must not be
registered as client events.

### Segment lifecycle

Combat entry creates Current. Damage can recover a missed entry notification;
healing and utility facts cannot start a standalone fight. Player combat state,
group combat state, and a short debounce determine closure.

Current and Overall receive accepted facts together. On closure, the exact
segment duration is added to Overall whenever the segment contains data. Fights
longer than five seconds may also enter bounded history; boss-only retention
filters history but never removes facts or elapsed time from Overall.

Numeric segment selections are history indices. When a new segment is inserted
at index 1, the `segmentArchived` subscriber increments existing numeric
selections so each window continues to show the same saved set.

### Aggregation boundary

`data/data.lua` is the public recording facade. New sources should call its
scalar `Record*` methods rather than mutate sets directly.
`data/data.aggregator.lua` owns the set and actor shapes, spell/detail tables,
totals, active time, healing verification fields, and death logs.

Healing retains three distinct values:

- combat-message total (`healing`);
- estimated effective amount (`effectiveHealing`);
- estimated overheal (`overhealing`), which the healing modes also draw as a
  dimmer continuation of the bar past the effective fill (a mode's
  `extraField`; `entry.extra` on display rows, `row.extra` texture placed by
  arithmetic from the row width, bar scale = max of value + extra).

Amounts without a readable health snapshot also increment
`unverifiedHealing`. Callers must not relabel these estimates as exact values.

### Parser registry

`Parser:AddGlobal` reads localized client format strings. `Parser:AddPattern`
is reserved for confirmed literal formats that have no available global name.
The compiler supports positional placeholders such as `%2$s` and currently
passes at most five captures to an adapter.

Mitigation trailers are removed before the base message is matched. Their type
and amount are held in file-local state for the duration of that one synchronous
dispatch and cleared before the next message.

Unmatched messages increment `unmatchedCountByEvent`; they are diagnostic only
and must never fail the event handler.

### Rendering

Core tickers run independently of display rebuilding and are scanned only when
the shortest registered ticker interval is due. A full rebuild occurs at a
fixed 250 ms cadence when data is dirty or a visible time-dependent view needs
clock updates. Raw-value views remain idle during quiet combat. Bars always
ease at fixed speed 5 between rebuilds without sorting, formatting, allocating
display entries, or reading the clock; only windows with visible movement are
visited.

Three signals remain separate:

- `Skada.dirty` requests content reconstruction.
- `window.layoutDirty` requests geometry and typography updates.
- `UI.hasActiveAnimations` keeps easing active until subpixel movement ends.

Hidden windows do not request continuous rendering.

### Window configuration

Each window owns mode, segment, geometry, visibility, lock, auto-switch, and
snap settings. `ui/ui.config.lua` is the only owner of the mirrored key list,
default application, migration, and primary-window compatibility mirror.

After changing a per-window key, call `UI:SyncLegacy(window)`. Only the primary
window is mirrored into the historical profile fields. Appearance and data
settings that intentionally apply to every window remain on the global profile.

### Settings

The settings dialog is Skada's own (`options/options.dialog.lua` for the
chrome, sidebar and pane, `options/options.controls.lua` for the control
renderers), built directly on this client's frame APIs — no widget library.
It replaced the vendored Ace3 stack under `libs/` (now deleted), whose every
rendering symptom here — blank EditBox values, an unscrolling scroll frame,
strata/level inversions, single-column panes — was a repair job in
`core/core.compat.lua`. Two design decisions bury the worst bug classes at
the root: sliders have NO value EditBox (the value lives in a plain
FontString, which cannot come up blank), and the dialog's layout is pure
arithmetic (nothing reads a rendered rect, so there is no reflow and a
control is laid out correctly the first time it is built).

`core/core.compat.lua` still loads first and fills in or repairs globals
this client lacks or other addons break (`string.match` is probed and
replaced when RollFor has clobbered it, `string.split`, the length-tracking
`table.*` functions, `table.sort`) and wraps `CreateFrame` so that
`GetWidth`/`GetHeight` report an explicit size while the client's rect still
reads 0 (the client only computes anchor-derived rects at render time, and
any layout that sizes a child from such a read synchronously would inherit
width 0). The wrapper's remaining fixes stay `.obj`-gated so BigDebuffs'
own bundled Ace3 keeps benefiting from them: an explicit size wins outright
and a rendered rect is divided by the effective scale for AceGUI frames (the
client reports anchor-derived rects in screen units, which fed back through
its Fill layout shrank the pane on every rebuild), TreeGroup's
`OptionsListButtonTemplate` rows are built from scratch (the client's
template OnLoad never populates the `.toggle`/`.text` fields TreeGroup
indexes), and `SetParent` re-derives the moved frame's strata and frame
level from its new parent, subtree included
(`SkadaCompat.InheritLayering`) — the client leaves both untouched on
reparenting. The same gap applies to Blizzard's shared `ColorPickerFrame`:
the compat layer hooks its OnShow to carry its layering down to its
Okay/Cancel children (toplevel off while shown, restored on hide).

The dialog root is a fixed 769×560 frame at HIGH strata — above the meter
windows (LOW) and the normal UI (MEDIUM), below DIALOG where the StaticPopup
confirmations for delete/reset live — not toplevel, `SkadaCompat.FixLevels`
applied after every build. Its chrome is the default UI's own: the untinted
dialog-box frame and header ribbon (`Style:ApplyDialogFrame`,
`Style:CreateDialogTitle`), tooltip-bordered inset panes for the sidebar
and the scroll pane (`Style:ApplyPane`), a red panel Close button and the
round panel X. The sidebar's rows are built from scratch (167x18 buttons
with the quest-log highlight on hover, the same highlight held lit with
gold text on the selected row): a General row, a mouse-disabled Windows header whose
right edge carries the plus button that creates a window
(`Skada.UI:CreateNew()` then `Options:SelectWindow`), and one indented row
per meter window. The pane is a NAMED ScrollFrame from
`UIPanelScrollFrameTemplate` — the template's own `<name>ScrollBar` drives
clipping and the scroll range natively, the mouse wheel is wired by hand
(the template omits it here) — with an explicit-size, anchorless scroll
child re-handed over via `SetScrollChild` after every height change plus
`UpdateScrollChildRect` (the client fixes the scroll range at SetScrollChild
time). Frame scripts are chained through `SkadaCompat.AppendScript`, never
`HookScript`: the client's HookScript runs the original handler without its
positional arguments, and the harness lints Skada's own files for it.

`options/options.controls.lua` renders the eight leaf types the schema
emits, one frame per spec, each carrying a back-reference to its spec:

- **toggle/select/color** — the default UI's check box, dropdown
  (UIDropDownMenuTemplate's art under a gold caption) and chat color
  swatch, each with its label; the select opens a Skada-owned popup
  wearing UIDropDownMenu's list backdrop, parented to the dialog root at
  DIALOG strata so the scroll child's clipping cannot cut it off;
- **range** — a from-scratch Slider frame (1.12 has no slider template)
  using the backdrop/thumb texture recipe proven in game, with the current
  value shown as a plain text label beside the gold caption and a `setup`
  re-entrancy flag around programmatic `SetValue` (the real client fires
  OnValueChanged for every programmatic SetValue);
- **color** — a swatch button configuring Blizzard's shared
  `ColorPickerFrame`, level-bumped above the dialog and re-layered through
  the compat hook before `Show()`;
- **input** — the one remaining EditBox (the window name), wearing
  InputBoxTemplate's border under a gold caption. Text is NEVER
  set at build time: the value is queued and a one-shot plain-Frame driver
  applies it once a render pass has placed the box (`GetLeft` answers
  non-nil; OnUpdate does not fire on EditBox frames here, and the dialog's
  arithmetic layout never reflows, so one placement suffices). Enter
  commits, Escape reverts to the last committed value;
- **execute/header** — a red panel button (UIPanelButtonTemplate, routed
  through StaticPopup confirmations; a full-width row keeps it at a
  button's width) and the classic centered gold heading with a
  tooltip-border line out to each edge.

`options/options.schema.lua` builds the whole options table fresh on every
call to `Schema:BuildOptions()` — a root group with a `general` group (every
global-profile row) and a `windows` group. The `windows` group's `args`
holds one nested group per meter window, keyed `window_<id>`, and nothing
else; each window's own group is built by `Schema:BuildWindowArgs(window)`,
whose `get`/`set` closures capture that specific `window` directly — there
is no shared "currently selected window" for these to resolve, since every
window's subgroup is rebuilt per pane. In the sidebar the Windows node is a
header rather than a page. `options/options.lua` is the public API other
code calls (`Open`/`Close`/`Toggle`/`SelectWindow`/`CycleWindow`/`Refresh`)
plus `selectedWindow` (which window's border is highlighted on screen and
which pane `SelectWindow`/`CycleWindow` navigate to) and the minimap
button.

Whenever the window list changes, a window is renamed, or a mode switch
auto-renames a window, call `Schema:NotifyChanged()`, which funnels into
`Options:Refresh()` — a no-op while the dialog is closed (Open rebuilds
everything anyway) and a sidebar+pane rebuild while it is open.
`windowListChanged` also calls `Options:GetCurrentWindow()`, whose self-heal
(falls back to `Skada.UI:GetActive()` when `selectedWindow` no longer
resolves in `Skada.UI.byID`) is what makes the panel recover after the
selected window is deleted.

## Extending the addon

### Add a meter mode

1. Add or populate an aggregate field through the `Data` facade.
2. Register a projection in `modes/modes.lua` with its actor field and optional
   detail field.
3. Add focused test coverage for actor values, detail values, text formatting,
   navigation, and empty data.

### Add a parser route

1. Prefer an existing localized global format.
2. Restrict the route to the smallest correct event list.
3. Adapt captures into an existing `Data:Record*` method.
4. Add fixtures for normal, critical, positional, ambiguous, and unmatched
   messages as applicable.

### Add a setting

1. Add a row specification to `OptionsSchema.pages`.
2. Keep persistence and side effects inside its setter.
3. Mark content dirty, mark layouts, or synchronize the primary window only as
   required by that setting.
4. Extend test coverage for both primary and secondary windows when scope
   matters.

## Verification

The global table compatibility repairs cache discovered list lengths while
checking their boundaries for external changes; a `table.setn` shrink
additionally truncates the table's tail, so Lua-5.0-style callers that
clear and refill a list (setn(0), insert, setn(display count)) keep tracked
length and contents in agreement. Sorting uses in-place
introsort with insertion sort for small ranges and a heapsort fallback at
the partition-depth limit. This bounds worst-case work to O(n log n) and
stack depth to O(log n), including sorted and duplicate-heavy input from
other addons using the global shim.

Run the test suite after changing runtime code, TOC order, SavedVariables,
parsing, or UI behavior:

```shell
python tests/run_tests.py
```

`python tests/benchmark.py` prints repeatable host-side parser and sorting
timings. Compare runs on the same machine and Lua runtime; these timings
do not measure client frame time. The performance suite separately checks
sort correctness and comparison bounds, retained memory, cached length
reads, and coalesced combat roster scans without wall-clock thresholds.

`tests/run_tests.py` is the orchestrator: it lints upvalue aliases, boots the
stubbed environment from `tests/stubs.lua`, and runs each suite in
`tests/suites/` in a fixed order, naming the failing suite on assertion
errors. The suites are stateful and sequential — later suites assert on data
created by earlier ones — so the order in the orchestrator's `SUITES` list is
part of the contract.

The test loader parses `Skada.toc`, so a missing file or load-order regression
fails before behavioral assertions run. It also reproduces RollFor's
captures-only `string.match` clobber before the addon loads, so the
probe-and-replace in `core/core.compat.lua` is exercised as it is in game,
nils `string.match` right after `core/core.compat.lua` loads so Skada's own
files stay Lua 5.0 pure, and checks locally aliased standard-library
functions used by runtime modules.
