# Nampower capability audit

An inventory of everything Nampower publishes to Lua, what Skada does with each
item today, and what is deliberately left on the chat-text parser. Source of
truth is the `nampower-source` checkout: `EVENTS.md`, `SCRIPTS.md`,
`UNIT_FIELDS.md`, `DBC_FIELDS.md` and `README.md`.

Two client extensions matter and both must be present:

- **Nampower** publishes the server's combat packets as Lua events with real
  GUIDs, spell IDs and unmitigated amounts.
- **SuperWoW-style unit tokens** let `UnitName`, `UnitHealth` and friends accept
  a raw GUID string. Every Skada aggregate is keyed by actor name, so without
  this the GUID-only events cannot be attributed. `combat/combat.nampower.lua`
  probes for it at login and stays inactive if it is missing.

## Where the numbers come from

`combat/combat.nampower.lua` owns the facts below whenever the ingest is active.
It sets a suppression flag on `combat/combat.parser.lua` for each one, so the
localized chat line for the same hit is dropped instead of double counted. Turn
the ingest off and every flag clears, restoring the chat path exactly.

| Fact | Nampower events | Skada entry point |
| --- | --- | --- |
| Spell damage | `SPELL_DAMAGE_EVENT_SELF` / `_OTHER` | `Data:RecordDamage` |
| Melee damage | `AUTO_ATTACK_SELF` / `_OTHER` | `Data:RecordDamage` |
| Environmental damage | `ENVIRONMENTAL_DMG_SELF` / `_OTHER` | `Data:RecordDamage` |
| Damage shields | `DAMAGE_SHIELD_SELF` / `_OTHER` | `Data:RecordDamage` |
| Healing and overhealing | `SPELL_HEAL_BY_SELF` / `_BY_OTHER` | `Data:RecordHealing` |
| Power gains | `SPELL_ENERGIZE_BY_SELF` / `_BY_OTHER` | `Data:RecordPower` |
| Misses and avoidance | `SPELL_MISS_SELF` / `_OTHER`, auto-attack victim state | `Data:RecordMiss` |
| Dispels | `SPELL_DISPEL_BY_SELF` / `_BY_OTHER` | `Data:RecordDispel` |
| Deaths | `UNIT_DIED` | `Data:RecordDeath` |

### What each event buys us over the chat line

- **No dropped lines.** The chat frame throttles and drops combat text under
  raid load. These events come off the packet handler.
- **No locale gap.** The parser's avoidance and resource-gain routes fall back to
  hardcoded English patterns where no client global string exists, so those
  facts under-count on other locales. The events carry no text at all.
- **Real spell IDs.** The parser has to guess an ID by correlating a spell name
  against recent casts. `SPELL_DAMAGE_EVENT_*` states it outright, so ranks and
  same-named abilities stop colliding.
- **Off-hand split.** `HITINFO_LEFTSWING` separates off-hand swings, which chat
  text cannot express. Skada records them as `Auto Attack (Off-Hand)`.
- **Exact overhealing.** The heal event carries the target GUID, so
  `Data:EstimateHealing` reads that exact unit's health instead of resolving a
  name to a unit token that may not exist. Heals on units outside the group's
  tokens are now verified rather than assumed fully effective.
- **Glancing and crushing blows** arrive as hit-info flags rather than a
  parenthesized suffix that only exists in English.

### Known lossy edges

- Skada's damage record carries one mitigation observation per hit, matching what
  a chat line can say. Nampower reports absorb, block and resist together, so the
  largest non-zero component is kept and the others are dropped. Widening this
  means changing the `RecordDamage` signature and the mitigation breakdown UI.
- `SPELL_DAMAGE_EVENT_*` reports a percentage rather than a raw amount when the
  aura type is `SPELL_AURA_PERIODIC_DAMAGE_PERCENT` (89). Skada currently records
  the number as given.
- `AUTO_ATTACK_*` collapses sub-damage components into a total. Weapons with
  elemental damage lose the per-school split, which the event does not carry.

## Still on the chat-text parser

Nampower publishes no equivalent, so these routes are never suppressed:

- **Interrupts.** No interrupt event exists. `UNIT_COMBAT_GUID` reports an
  `INTERRUPT` action but names only the interrupted unit, not the interrupter.
  `SPELL_FAILED_OTHER` gives a caster and spell but no cause.
- **Crowd control and CC breaks.** Derived from aura scans plus
  `CHAT_MSG_SPELL_BREAK_AURA`.
- **Aura uptime (buffs and debuffs).** See below.

## Available and not yet used

Ranked by what they would buy a combat meter.

### Aura uptime from events instead of scans

`BUFF_ADDED_*`, `BUFF_REMOVED_*`, `DEBUFF_ADDED_*`, `DEBUFF_REMOVED_*` fire for
every unit the client tracks and carry the unit GUID, spell ID, stack count,
caster level, raw aura slot, and a state code separating a genuine add or remove
from a stack change. `AURA_CAST_ON_SELF` / `_ON_OTHER` add the caster GUID and
the spell duration, and fire even when the 32-buff or 16-debuff cap would have
hidden the aura from a scan.

`tracking/tracking.auras.lua` today polls `UNIT_AURA` and rescans unit tokens on
a queue. Rewiring it would give exact application and fall-off timestamps, correct
attribution of a debuff to its caster, and uptime for units that never occupy a
unit token. It is a self-contained project against that one module and is the
largest remaining accuracy win.

### Interrupts, partially

`SPELL_START_OTHER` gives a caster GUID, spell ID and cast time; a subsequent
`SPELL_FAILED_OTHER` for the same caster says the cast ended badly. Correlating
that with a known interrupt ability landing on the caster in the same window would
attribute interrupts by GUID. It is inference, not a direct signal, so the chat
route stays the fallback.

### Cast counts and cast failures

`SPELL_CAST_EVENT`, `SPELL_START_*`, `SPELL_GO_*`, `SPELL_FAILED_*`,
`SPELL_CHANNEL_START` and `SPELL_CHANNEL_UPDATE` describe the full cast lifecycle
including item-triggered spells, channel duration and pushback. A cast-count or
ability-usage mode would come straight from these.

### Threat estimator inputs

`threat/threat.estimate.lua` already consumes `SPELL_GO_SELF` / `_OTHER` for
targets-hit counts. `GetSpellRec` and `GetSpellRecField` expose the client's DBC
spell record (school, cast time, mana cost, effects, durations), which the
estimator could use instead of its own tables. The OctoWoW Threat API stays
authoritative regardless.

### Unit state without token spam

The `_GUID` unit events fire once per unit rather than once per registered token,
and carry flags saying which tokens the unit currently matches. Skada registers
none of them: Nampower warns they fire for every unit the client tracks and flood
busy zones, and the ingest already learns a unit's name from the combat event
that damaged it. A death-recap health timeline would be the reason to revisit
`UNIT_HEALTH_GUID`.

### Lua helpers not currently called

- `GetUnitData` / `GetUnitField` read raw unit fields by token or GUID, with a
  party-member fallback for units the object manager has not loaded.
- `GetSpellRec` / `GetSpellRecField` / `GetSpellIconTexture` read spell records
  and icons without a spellbook lookup.
- `GetRaidTargets` returns the raid-marker to GUID assignment, which would let a
  window label enemies by mark.
- `CombatLogFlush` forces the combat log file buffer to disk, relevant to the
  combat-logging toggle.

Every function that returns a table reuses one table across calls. Extract the
values immediately or pass `1` as the `copy` argument.

## Version and CVar notes

Nampower 4.5.0 and later enable an event as soon as something registers for it.
Older builds gate several behind CVars, so `Nampower:Enable` sets
`NP_EnableSpellHealEvents`, `NP_EnableSpellEnergizeEvents`,
`NP_EnableAutoAttackEvents` and `NP_EnableSpellGoEvents` on activation. Setting
them on a newer build does nothing.

The ingest owns its own event frame rather than using `Skada:RegisterEvent`, for
two reasons: the shared runtime gates registration on `C_EventUtils.IsEventValid`,
which does not know Nampower's custom event codes, and it forwards only seven
payload arguments where `AUTO_ATTACK_*` carries nine.

`/skada status` reports which source is live and how many events it has seen.
