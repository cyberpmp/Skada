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
|-- combat/     Combat-text parser and routing
|-- modes/      Meter-mode projections
|-- ui/         Window presentation, rendering, reporting, and docking
|-- options/    Settings schema, widgets, shell, and minimap entry point
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
| Foundation | `core/core.common.lua`, `core/core.defaults.lua`, `core/core.runtime.lua`, `ui/ui.style.lua` | Compatibility helpers, profile defaults, lifecycle, events, tickers, internal messages, rendering policy, and shared visuals |
| Identity and data | `data/data.identity.lua`, `data/data.aggregator.lua`, `data/data.boss.lua`, `data/data.segments.lua`, `data/data.navigation.lua`, `data/data.lua`, `data/data.reset.lua` | Roster and pet ownership, aggregate mutation, boss recognition, segment lifecycle, history navigation, the data facade, and reset policies |
| Threat | `threat/threat.estimate.lua`, `threat/threat.lua` | Combat-scoped local estimates and the authoritative OctoWoW Threat API v4 provider |
| Enrichment | `tracking/tracking.spells.lua`, `tracking/tracking.casts.lua`, `tracking/tracking.auras.lua`, `tracking/tracking.damage.lua`, `tracking/tracking.group.lua`, `tracking/tracking.lua` | Spell metadata, cast correlation, dispels, interrupts, aura uptime, last-hit evidence, and group observation |
| Parsing and projection | `combat/combat.parser.lua`, `modes/modes.lua` | Combat-text routing and projection of aggregates into meter modes |
| Window UI | `ui/ui.config.lua`, `ui/ui.presenter.lua`, `ui/ui.rows.lua`, `ui/ui.snap.lua`, `ui/ui.report.lua`, `ui/ui.lua` | Per-window persistence, display models, pooled row rendering, snapping, reporting, and window composition |
| Settings and entry points | `options/options.widgets.lua`, `options/options.schema.lua`, `options/options.shell.lua`, `options/options.minimap.lua`, `options/options.lua`, `commands/commands.lua` | Native controls, declarative settings, panel shell, minimap access, settings facade, and slash commands |

Modules loaded later may reference tables created earlier. Event callbacks
resolve cross-module state at call time so initialization remains ordered and
explicit.

## Data flow

1. `combat/combat.parser.lua` compiles client combat formats once and routes
   only the chat events on which each format can occur.
2. Tracking services enrich sparse text with spell IDs, GUIDs, aura sources,
   dispel snapshots, interrupt casts, and last-hit evidence.
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
- estimated overheal (`overhealing`).

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

Core tickers run independently of display rebuilding. A full rebuild occurs at
the configured refresh interval when data is dirty or a visible live view needs
updates. Bar easing may continue between rebuilds without sorting, formatting,
or allocating display entries.

Three signals remain separate:

- `Skada.dirty` requests content reconstruction.
- `window.layoutDirty` requests geometry and typography updates.
- `UI.animateUntil` keeps one-off easing active briefly after a rebuild.

Hidden windows do not request continuous rendering.

### Window configuration

Each window owns mode, segment, geometry, visibility, lock, auto-switch, and
snap settings. `ui/ui.config.lua` is the only owner of the mirrored key list,
default application, migration, and primary-window compatibility mirror.

After changing a per-window key, call `UI:SyncLegacy(window)`. Only the primary
window is mirrored into the historical profile fields. Appearance and data
settings that intentionally apply to every window remain on the global profile.

### Settings

`options/options.schema.lua` describes pages and rows as data.
`options/options.widgets.lua` creates native controls,
`options/options.shell.lua` owns panel navigation and scrolling, and
`options/options.lua` owns selection and the page cache.

Rows must derive their state from `get` functions during `refresh`; cached rows
must not retain a particular window. Per-window setters resolve the currently
selected window at invocation time.

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

Run the test suite after changing runtime code, TOC order, SavedVariables,
parsing, or UI behavior:

```shell
python tests/run_tests.py
```

`tests/run_tests.py` is the orchestrator: it lints upvalue aliases, boots the
stubbed environment from `tests/stubs.lua`, and runs each suite in
`tests/suites/` in a fixed order, naming the failing suite on assertion
errors. The suites are stateful and sequential — later suites assert on data
created by earlier ones — so the order in the orchestrator's `SUITES` list is
part of the contract.

The test loader parses `Skada.toc`, so a missing file or load-order regression
fails before behavioral assertions run. It also forces the Lua 5.0
`string.match` compatibility path and checks locally aliased standard-library
functions used by runtime modules.
