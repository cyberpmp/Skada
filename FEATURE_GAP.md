1# Skada Vanilla Feature Gap

This document compares the current clean-room addon in this directory with the
bundled `resources/Skada` reference (Skada 1.8.3). The reference targets a
modern client with `COMBAT_LOG_EVENT_UNFILTERED`, Ace3, and several optional
libraries; it is a behavior and feature baseline, not a drop-in Vanilla
implementation.

Status used below:

- **Implemented** — available in the current addon.
- **Partial** — the core behavior exists, but the reference exposes more
  detail, controls, or presentation.
- **Missing** — not currently implemented.
- **API-limited** — requires data or client/server APIs that Vanilla does not
  provide by itself.

## Executive summary

The current addon has a solid Vanilla foundation: localized combat-chat
parsing, ClassicAPI identity/cast/aura enrichment, reliable combat segments,
multiple bar windows, smooth rendering, live OctoWoW threat, and basic chat
reporting. It deliberately avoids the original Skada's Ace3 framework and
modern CLEU event model.

Power/resource gains, debuff/buff uptime, damage/healing target breakdowns,
and damage avoidance/mitigation tracking are now implemented (see the tables
below). The remaining functional gaps are overhealing/total healing (an
intentional accuracy tradeoff, not an oversight), friendly fire, an enemies
overview, richer reports, and configuration/themes. Threat is authoritative
for OctoWoW, but remains server-snapshot based and therefore cannot be made
synchronous by Lua or ClassicAPI alone.

## Core data and accuracy

| Area | Current Vanilla addon | Original Skada reference | Gap / consequence |
|---|---|---|---|
| Event source | Localized `CHAT_MSG_COMBAT_*` and spell/aura events | `COMBAT_LOG_EVENT_UNFILTERED` CLEU | **API-limited.** Vanilla text has less context and fewer fields. |
| Identity | ClassicAPI GUID/unit/roster enrichment | CLEU GUIDs plus unit/roster data | **Partial.** Strong for observed units; unknown/off-screen sources remain weaker. |
| Combat boundaries | Regen events plus group combat state and debounce | CLEU activity, reset/wipe/instance logic | **Partial.** Robust against quiet swings and HoT ticks; fewer encounter-specific reset rules. |
| Current/Overall/history | Current, Overall, numbered recent fights | Current, Total, numbered fights, persistent sets | **Partial.** Persistent/manual saved sets are missing. |
| Segment naming | Mob name from observed combat text | Mob/encounter naming, boss IDs, instance metadata | **Partial.** No boss/encounter database integration. |
| Memory model | Compact aggregates, pooled UI rows, bounded history | Rich per-event/player/spell/death structures | **Different tradeoff.** Current version is lighter but retains less forensic detail. |
| Localization | Uses Vanilla global combat strings | Localized CLEU tables and UI locale files | **Partial.** Combat parsing is locale-aware, but the UI is primarily English. |

## Meter modes

| Original Skada feature/module | Current status | Notes and remaining work |
|---|---|---|
| Damage | **Implemented** | Player totals, spell drill-down, class bars, crit/min/max/count basics. Avoidance (dodge/parry/resist/immune/miss) and mitigation (blocked/absorbed/resisted/glancing/crushing) are now tracked and surfaced via the actor tooltip, since the bar-row UI has no literal column layout to add. |
| DPS | **Implemented** | Active-time DPS projection. Needs more detailed effective-duration and column options. |
| Damaged mobs / target breakdown | **Implemented** | New "Damaged Targets" mode drills a player's damage down by target name (reuses the existing spell-drilldown UI with a target-keyed detail table instead of a spell-keyed one). |
| Damage Taken | **Implemented** | Totals, player bars, spell drill-down. |
| DTPS and mitigation columns | **Partial** | Blocked/absorbed/resisted amounts and glancing/crushing flags are now parsed from the trailer Vanilla appends to hit messages (e.g. "(20 blocked)") and totaled per actor as `mitigated`, plus hit/avoid counts; shown via tooltip, not as bar-row columns. |
| Healing | **Implemented** | Healing totals, HPS, spell details, critical/min/max basics. |
| Overhealing | **Missing** | Unchanged by design: Vanilla text does not reliably expose overheal, and this addon deliberately avoids inventing an effective-healing figure from race-prone health snapshots (see README). |
| Total Healing | **Missing** | Combined effective healing plus overhealing mode is not present (depends on Overhealing above). |
| Healing targets | **Implemented** | New "Healing Targets" mode drills a healer's output down by recipient. |
| Dispels | **Implemented** | Cast/aura correlation and dispel counts. More detailed dispel type/target columns would close the gap. |
| Interrupts | **Implemented** | Correlated interrupt confirmations and spell details. Original has richer interrupted-spell presentation. |
| Crowd control | **Partial** | CC applications, duration, and breaks are tracked. The original has broader CLEU coverage and more detailed break attribution. |
| Deaths | **Partial** | Death counts are present, and each death now logs a timestamped, killing-blow entry (source + spell, best-effort from the most recent observed hit on that unit) in the same player's detail drilldown. Resurrection, health/absorb snapshots, and post-death event detail are still not tracked. |
| Threat | **Partial / authoritative** | Live OctoWoW `TWT_UDTSv4` threat, percentage, tank, and range state. No Overall/history, no synchronous client API, and no standalone solo data because the server requires PARTY/RAID. |
| Power gains | **Implemented** | New "Power Gained" mode tracks mana/rage/energy gained per player, with spell-level drilldown (Bloodrage, Life Tap, Blessing/Judgement of Wisdom, etc.). Mixed resource types on one bar are rare in Vanilla since a class typically has one primary resource. |
| Debuffs | **Implemented** | New "Debuffs" mode tracks harmful-aura applications and uptime, attributed to the caster (consistent with how CC is already tracked), via a generalized version of the existing CC aura scanner. Per-target breakdown is not included. |
| Buffs | **Implemented** | New "Buffs" mode tracks beneficial-aura applications and uptime the same way; unattributed buffs (no observable caster) fall back to attributing to the buffed unit itself. |
| Friendly Fire | **Missing** | No friendly-fire source, spell, or target breakdown. |
| Enemies | **Missing** | No enemy damage/threat/taken overview mode. |

## Threat-specific comparison

The original module calls `UnitDetailedThreatSituation()` and renders raw
threat, relative percentage, TPS, target selection, and warning effects. On
this server, the equivalent data is delivered by the Equadis/Turtle protocol:

```text
SendAddonMessage("TWT_UDTSv4", "limit=NN", "PARTY" or "RAID")
TWTv4=name:tank:threat:percent:melee;...
```

Current Skada correctly uses this server-authoritative path. It also clears
data on target changes, distinguishes same-named mobs by GUID, expires stale
rows, and avoids accumulating estimated threat in combat segments.

Remaining threat gaps are presentation/transport gaps, not calculation bugs:

- TPS is not currently shown as a dedicated column.
- Threat warnings, sounds, glow, and configurable thresholds are missing.
- Focus/target-target threat selection is missing.
- Exact instant updates require a server push/event or a new threat opcode;
  ClassicAPI has no hidden local threat table to expose.

## Window and navigation behavior

| Capability | Current status | Original Skada behavior |
|---|---|---|
| Bar display | **Implemented** | Lightweight custom bar display using bundled Skada textures/font. |
| Multiple windows | **Implemented** | Independent mode, segment, geometry, visibility, autoswitch, snapping. |
| Smooth refresh | **Implemented** | Up to 60 Hz visual repaint with eased fills; source data remains event/server driven. |
| Mode/segment traversal | **Implemented** | Right-click navigation and header controls model the original traversal. |
| Auto Current/Overall | **Implemented** | Per-window autoswitch; Threat intentionally remains live/current only. |
| Screen/window snapping | **Implemented** | Flush docking, overlap docking, parent-size adoption, and edge alignment. |
| Inline display | **Missing** | Original includes `InlineDisplay.lua`. |
| Broker display/minimap icon | **Missing** | Original integrates LibDataBroker and LibDBIcon. |
| Themes/status bars/fonts | **Partial** | One primary visual style; no theme manager or SharedMedia selector. |
| Tooltips | **Partial** | Useful basic tooltips; original has mode-specific columns, subviews, and configurable tooltip detail. |
| Scroll/navigation controls | **Implemented** | Mouse wheel and mode/segment buttons are present. |
| Window locking/resizing | **Implemented** | Includes drag, resize, lock, snap, and persisted geometry. |
| Profiles | **Missing** | No AceDB profile management or profile copy/reset UI. |
| Options panel | **Missing** | No AceConfig/AceGUI settings interface; slash commands cover only common controls. |

## Reporting and integration

| Capability | Current status | Gap |
|---|---|---|
| Chat report button | **Implemented** | Guild, Party/Raid, Say, Whisper; Whisper has a recipient field. |
| Report formatting | **Partial** | Compact top-level lines work; original supports configurable mode/set/max-lines and richer valuetext/columns. |
| Report command | **Partial** | Button workflow exists; a full `/skada report` argument model is not implemented. |
| Combat file logging | **Implemented** | Toggles `LoggingCombat()` for Chronicle upload. |
| Chronicle integration | **Partial** | Correctly produces the client log; no in-game upload or report browser. |
| Announcements | **Missing** | No CC-break or threat-warning announcements comparable to original modules. |

## Original Skada systems not yet represented

The reference also contains infrastructure that is intentionally absent from
the Vanilla build:

- AceAddon/AceDB/AceConfig/AceGUI/LibStub dependency stack.
- SharedMedia theme, font, border, background, and status-bar registries.
- LibWindow positioning and LibDataBroker/LibDBIcon display integrations.
- Boss-ID and encounter reset logic.
- CLEU event registration/filtering and rich per-event death logs.
- Persistent segments, wipe mode, return-after-combat, hide-solo/PvP rules,
  and configurable reset policies.

These are not all desirable to port verbatim. Recreating the framework stack
would work against the addon’s lightweight/performance goal; equivalent native
Vanilla controls are preferable.

## Recommended implementation order

1. ~~Add richer damage/healing fields that are actually available from
   ClassicAPI/chat: misses, mitigation, target breakdowns, spell statistics,
   and healing targets.~~ **Done.** Misses/dodges/parries/resists/immunities
   and blocked/absorbed/resisted/glancing/crushing mitigation are tracked
   (`Data:RecordMiss`, the `mitigationType`/`mitigationAmount` trailer capture
   in `Parser.lua`); "Damaged Targets" and "Healing Targets" modes provide the
   target breakdowns.
2. ~~Add power/resource modes from ClassicAPI-compatible resource events.~~
   **Done.** The "Power Gained" mode covers mana/rage/energy gains.
3. ~~Add debuff/buff uptime modes using the existing aura scanner, with strict
   source-GUID attribution and no out-of-combat segment creation.~~ **Done.**
   `Utility:ScanAuraKind`/`ScanAll` generalize the existing CC scanner to
   general debuffs/buffs; both stay gated by the same combat-segment rules CC
   already used.
4. ~~Expand death logs with timestamped recent events, killing source, and
   resurrection correlation where the client exposes enough information.~~
   **Partially done.** Timestamped killing-blow entries are logged per death;
   resurrection correlation is still missing.
5. Add report presets, configurable line count, and a native options panel.
6. Add optional themes/status-bar choices without importing Ace3.
7. Coordinate an OctoWoW server/API enhancement for push-based threat updates,
   TPS/status fields, and target GUIDs if truly instant threat is required.

## Notes on the newly-added parsing

Miss/dodge/parry/resist/immune text and the mana/rage/energy "gains" text are
registered in `Parser.lua` as literal English `AddPattern` strings rather than
`AddGlobal` lookups, matching the precedent already set there for interrupts
and deaths. This client's `GlobalStrings.lua` ships packed inside MPQ
archives, so the exact global variable names for these messages could not be
confirmed; the literal patterns were instead validated against real text
captured in this install's own `Logs/WoWCombatLog.txt`. An unmatched line
degrades to the existing `Parser.misses` counter, never a hard failure, so a
locale mismatch only means the stat under-counts rather than errors. Non-enUS
clients should treat these specific patterns (misses/avoids/power gains) as
lower-confidence than the original damage/heal/death patterns until verified
against their own combat log output.

## Bottom line

Power gains, debuff/buff uptime, damage/healing target breakdowns, and
damage avoidance/mitigation tracking close out most of the "richer detail"
gaps identified above. What remains is mostly presentation infrastructure
(report presets, options panel, themes), modes not yet implemented (friendly
fire, an enemies overview), and overhealing/total healing, which this addon
intentionally declines to fake with unreliable health-snapshot data.
