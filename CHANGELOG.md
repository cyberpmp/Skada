# Changelog

All notable changes to the PMP Skada rewrite are documented here.

## 3.0.1 - 2026-10-02

### Fixed

- Live threat no longer accepts a threat table sent by another player. Any
  group member could post a forged Threat API v1 reply as an addon message
  and have it shown as live server data. Packets from a roster member other
  than you, guild- and battleground-channel packets, and packets with escape
  sequences in names, non-finite values or oversized tables are dropped, and
  the first one dropped is reported in chat.
- On servers that never answer threat queries, Skada no longer sends one to
  the group every half second for the whole session: after eight unanswered
  queries it re-asks every 15 seconds (and once per target switch) until a
  reply arrives or the group changes.
- A hunter pet renamed after a group member no longer takes that member's
  damage, healing, threat and deaths. Players claim their names before pets
  are read, and a pet whose name is taken gets its own "Name (Owner)" entry,
  so with Nampower its numbers go to its real owner. Two hunters' pets with
  the same name no longer both land on the last owner either.
- A unit outside the group wearing a member's name (a stranger's pet, a mob
  named like a group pet) no longer overwrites that member's identity when
  it is targeted, moused over or nameplated, and is no longer used to price
  the member's overhealing. With Nampower its events are filed under
  "Name (other)" and credit nobody. Without Nampower, chat text carries no
  GUIDs, so a shared name is still credited to the group member.
- Boss detection ignores player-controlled units, so a pet renamed after a
  boss no longer marks a trash fight as that encounter.
- Chat reports strip `|` escape characters and cap each line at 255 bytes.

### Changed

- Threat tooltips name the source of server threat data as "Server" instead
  of a specific server name, and the threat initializer is listed as
  "live threat", matching the others.
- The README and docs describe Skada as a WoW Vanilla 1.12.1 (ClassicAPI)
  meter rather than a single-server one, name the threat protocol Skada
  speaks (Threat API v1) instead of a generic "server", and carry a new hero
  image and refreshed window and settings screenshots, palette-compressed to
  keep the repository small.

## 3.0.0 - 2026-10-01

### Fixed

- Left-clicking the minimap button now hides every meter window, not just
  the active one, and the next click shows back exactly the windows it hid:
  a window you hid yourself stays hidden. A window that failed to build no
  longer blocks the show (its stale flag used to make every click a hide).
- Saved fights no longer vanish while dragging the Saved fights slider:
  it now applies the value you let go at, instead of trimming the history
  at every lower value the drag passed through. A page refresh while the
  slider is still held (a window renaming itself as combat starts) no
  longer applies the value the drag was passing.
- An open settings dropdown now closes when you click anywhere outside it,
  the dropdown itself included, like the default UI's menus. Before, only
  picking an entry or closing the dialog put the list away.
- Accepting the "Reset Skada data for the new encounter context?" popup
  after a fight has started no longer wipes that fight; an automatic reset
  never runs mid-fight.
- A snap gap of 4 now sticks. An old one-off fix-up turned 4 into 0 on
  every load; it now runs once. Profiles from before snap distance and gap
  moved to General get every window set to the first window's values, so
  the General sliders show what each window really uses.
- Pressing Enter in a window's name box without changing the name no
  longer marks the window as custom-named (which stopped its title from
  following its mode). An empty name is refused and the stored name comes
  back in the box. Leaving the page while typing no longer leaves the
  hidden box holding the keyboard.
- Settings that changed outside the dialog (a mode picked from the meter's
  menu, a combat switch, a window shown or hidden) now repaint an open
  settings page at once. A setting that had become clickable again could
  stay dimmed and ignore clicks until the page was reopened.
- Slider and window-name tooltips show again; they were attached to frames
  that never receive the mouse.
- Skada's replacement `table.insert`/`table.remove` no longer rescan the
  whole list on every call, which made building or draining a long list
  quadratic for every addon in the client. Its `table.sort` raises
  "invalid order function for sorting" like the native one when given a
  comparator that is not a strict order, instead of looping forever.
- Bagshui's bags no longer come up blank with Skada loaded
  (`Components/Rules.lua:765: assertion failed!`). Skada's replacement
  `table.getn`/`insert`/`remove`/`setn` (needed because this client's
  native length tracking goes stale on `t[n + 1] = v` appends) probed
  `t[1]` through the table's metatable to find the length. Bagshui's rule
  engine gives its item table a case-insensitive `__index` that asserts on
  any miss and clears that table through `table.getn`, so the length check
  itself tripped the assertion on every item. The shims, `table.sort`
  included, now read and write raw, as the native Lua 5.0 table library
  does.
- Estimated threat for area spells never received Nampower's targets-hit
  count. The threat estimator listened for the spell-go events on Skada's
  shared frame, whose registration is gated on the client's event validator,
  which does not know Nampower's custom codes, so the listener was dead in
  game. The ingest's own frame now republishes spell-go on the internal bus
  and the estimator subscribes there. The test stub now refuses Nampower
  codes on the shared frame the way the client does, so this class of bug
  fails the suite instead of failing silently.
- A totem or other tokenless summon no longer appears as its own actor when
  mobs hit it, miss it, or it dies. Summons are sources only: a totem is hit
  by every mob near it and dies by design when it fires, and none of that
  belongs in damage taken, avoids or deaths, for the totem or its owner.
  Group pets on a pet token keep their own rows as before.

### Changed

- The settings dialog was reorganized around what a player is looking for.
  The old General page, one 29-control scroll of behavior, appearance, data
  and reset rows, is now three short pages: General (tracking, minimap,
  combat-file logging), Appearance (everything every window shares: window
  border, bar texture, font, number format, bar borders, class and spell
  colors, own-row highlight) and Data (fight history, the reset button, the
  automatic-reset policies). Each window's page now fits the dialog without
  scrolling, in three sections: Window (name, visible, locked, title bar,
  snapping on or off, size matching), Display (mode, segment, combat mode,
  automatic segments) and Layout (size, rows, font size, opacities). It opens with
  the window's name as its title and a subtitle saying fonts and colors are
  shared and live under Appearance, so the per-window versus shared split
  is visible instead of guessed at. Snap distance and gap left the window
  pages for General: they are one setting for every window, not something
  anyone tunes per window. Delete window moved from the last row of the
  page, which needed scrolling to reach, to the page's title row beside the
  window's name.
- The settings dialog lost its boxes within the box. The sidebar and the
  page no longer sit in their own tooltip-bordered insets; they share the
  dialog's surface with one hairline between them, section headings sit at
  the left with a single rule trailing off to the right instead of being
  framed between two strips, and the scrollbar with its arrow buttons only
  appears when a page is taller than the pane, which none of the stock
  pages are now.
- The title row of a meter window no longer draws its own tinted strip and
  hairline. The window backdrop is the only background, so the title and
  its buttons sit directly on it; at low window opacity the strip had read
  as a ghost band floating over the bars.
- A combat mode is now always a round trip: the window switches to it when
  combat starts and returns to its previous mode, and its previous segment
  (a window parked on Overall or a saved fight comes back there), when
  combat ends. The way back is saved, so a /reload mid-fight or a window
  created mid-fight still returns; a mode or segment picked by hand during the fight
  is kept. The separate "Return after combat" toggle asked the same
  question twice and is gone; a window that should always show one mode
  just sets that mode. The old flag is dropped from saved profiles.
- Settings rows now line up: a row holds only controls of one kind (check
  boxes beside check boxes, sliders beside sliders, dropdowns beside
  dropdowns), every page opens with a title and description, headings get
  air above them so sections read as blocks, and the dialog grew from 560
  to 640 tall so a window page shows whole.
- Settings that do not apply right now dim instead of sitting there live:
  the custom bar color while class colors are on, the border color with no
  border, bar border color with bar borders off, size matching with that
  window's snapping off, snap distance and gap while no window snaps, the
  segment on a live mode, and the Nampower toggle while Nampower is not
  loaded (it was clickable before). Toggling the controlling setting
  updates its dependents immediately, without a page rebuild.
- Saved profiles no longer keep a copy of the first window's settings at
  the profile level. Every window owns its settings, and the copy, kept for
  code from before multiple windows, is removed from the saved profile once
  on load, along with the retired border on/off flag and the old refresh
  and animation keys. The window border style is now the only border
  setting. Profiles saved before 2.0 still load from their windows' own
  settings; only the early adjustments of old default values are gone.
- Switching settings pages no longer creates frames. Controls and sidebar
  rows are pooled and rebound to the page being shown; the old dialog built
  a fresh set of frames on every sidebar click and every refresh, and this
  client never releases a frame. The scroll position resets to the top when
  the page changes, and the dialog shows the addon version in its corner.
  A combat switch redraws an open dialog once for every window instead of
  once per renamed window, and a redraw of the page on screen keeps an
  open dropdown open and a name being typed.

### Added

- `/skada status` names the build stamp (`X-Build` in the toc) so same-day
  rebuilds of one version can be told apart, and each uncredited-source line
  now also says how the registry sees the source and its owner (absent,
  refused, plain, tracked, owned) and how many owner reads were tried.

## 2.0.4 - 2026-09-29

### Fixed

- Damage from your totems and other tokenless summons (Fire Nova Totem, Magma
  Totem, Searing Totem) is credited to you again with Nampower on. Before
  2.0.3 it was credited only by accident: a Fire Nova Totem despawns before
  its damage packets are read, the client could no longer name it, and the
  blank name fell through to the player. 2.0.3 closed that hole because it
  also credited strangers' summons to you, which took the totems with it.
  The ingest now reads a summon's owner off the unit while it still exists
  (the spell-go packet that precedes the damage) and merges its hits into the
  owner like a pet, so the rows read "[Fire Nova Totem IV] Fire Nova". A
  groupmate's summon merges into the groupmate; a stranger's stays dropped.
  Chat-text mode (Nampower off) has no unit to read and cannot attribute
  totems, as before.
- Dispels were counted twice with Nampower on. The packet recorded one, and
  the aura-snapshot route that exists for chat-text mode (a buff missing from
  the target after your cast) recorded it again; only the chat "is removed"
  line had been silenced. The snapshot route now stays quiet whenever the
  packet is authoritative. Abolish Poison still counts every tick that
  removes a poison, since each is a real dispel.
- A Fire Nova Totem the client never names, at its spell-go or at damage
  time, is still credited to you: your own spell-go for a "... Totem" spell
  vouches for an unnamed caster dealing that totem's spell within 12 seconds
  ("Fire Nova Totem" for "Fire Nova", "Magma Totem" for "Magma Totem",
  "Searing Totem" for "Attack"). A caster the client can name never goes
  through this, so a stranger's visible totem is never taken.

### Added

- `/skada status` now reports spell-go and unresolved-GUID counts and lists
  the last five damage sources the Nampower ingest could not credit, with
  the source's name or GUID, the spell, whether the unit was still live, and
  what the client said about its owner. Send that output with a report of
  missing damage.

## 2.0.3 - 2026-09-28

### Added

- `/skada reset` wipes all fight data immediately. It skips the confirmation
  prompt on purpose, since typing the command is deliberate. A reset taken
  mid-fight, by the command or the confirmation popup, now opens a fresh
  segment straight away instead of dropping heals, deaths and counts until
  the next damage line.

### Fixed

- Estimated threat for two mobs sharing a name (a pull of two Boars) no longer
  erases the first mob's table when the second is targeted. Chat-log damage
  now lands on the live same-named mob you are targeting (a corpse or a
  same-named pet on the target never qualifies), and switching back shows the
  earlier threat instead of an empty window. Nampower damage and death packets
  key by the exact unit, so hits on the untargeted twin no longer land on the
  targeted one. A name-only death line removes a dead target's table, or
  keeps every same-named mob still alive on your target, focus, mouseover or
  a groupmate's target and removes the rest; with none in sight every table
  under the name goes, as before. A corpse parked on your target stops the
  removal there even when nothing was ever tracked under its GUID, so a live
  twin tracked elsewhere is not swept out with it. Only your own hits (your
  pets merge into you) may read the live target as the mob a chat line names;
  a groupmate's line keeps whatever mob the name last pointed at. The target
  check for your own swings is cached between lines and refreshed on target
  changes and removals, so it costs no unit calls per swing. Mobs that evade
  or despawn without a death line stop splitting heal threat after 30
  seconds, and their table and name mapping go with them, so a stale mapping
  cannot re-register an expired mob on the next hit.
- Damage from a caster the client could not name, such as a stranger's summoned
  Infernal landing "Inferno Effect" nearby, was credited to you. Blank or
  missing source names no longer resolve to the player; only a literal "You"
  does. The same applies to the Nampower packet path when a caster GUID cannot
  be resolved.
- The threat window no longer waits two seconds after every target switch
  before showing estimated threat. Solo players, and groups that have never
  heard from a threat server, get the local estimate on the first tick.
  Grouped players with a working server keep a short hold (0.75s) so the
  reply paints first instead of an estimate it would reshuffle a moment
  later; a live server reply always replaces the estimate as soon as it
  lands. Joining or leaving a group resets the hold, so a new roster without
  a server is not kept waiting on the old group's packets.
- A caster the client cannot see prints as an empty name in chat. That empty
  name no longer becomes the fight's segment name or the source in a death
  recap ("Killed by  (Inferno Effect)"); it is treated as unknown everywhere.
  The recap still keeps the spell that landed, so a death you could not name
  reads "Unknown cause (Inferno Effect)" instead of a bare "Unknown cause".
- Heals, power gains, interrupts and deaths recorded while only the group is
  fighting - you standing outside the mobs' reach - now open the fight
  segment instead of being dropped. Unless you were in combat yourself, a
  segment only opened on damage lines.
- Meter windows with the title bar hidden anchored the first bar flush against
  the top border. Headless windows now keep the same 6px inset above the first
  bar that every window keeps beside and below the bars.

### Changed

- Window height no longer includes the spacing after the last bar, so the
  bottom margin matches the side margins exactly instead of running one bar
  spacing taller. Free-floating windows keep their row count and re-derive
  their height on the next layout. Snapped windows, which are stored by their
  bottom-left corner, are migrated by re-deriving the row count from the
  pixel height the window was saved with, so docked stacks stay seamless
  without being dragged again - including headless windows (the new top inset
  would otherwise have made them 6px taller) and full 30-row windows.

- The README now carries a non-affiliation and trademark disclaimer and states
  that no game client files are redistributed.

### Removed

- The bundled Expressway font. Its freeware terms do not clearly permit
  redistributing the font file, so it is no longer shipped or offered in the
  font list. Saved settings that referenced it fall back to the client's
  default font rendering.

## 2.0.2 - 2026-09-08

### Added

- Read combat from Nampower's server events instead of localized chat text when
  Nampower and GUID-addressable unit tokens are both available. Damage, healing,
  power gains, misses and avoidance, dispels and deaths now arrive with real
  GUIDs, real spell IDs and real amounts, with no dropped chat lines and no
  locale-specific patterns. The matching chat routes are suppressed while the
  ingest is active, so nothing is counted twice, and interrupts, crowd control
  and aura uptime keep flowing from the text parser, which has no Nampower
  equivalent. New "Use Nampower combat events" setting under General; `/skada
  status` names the live source.
- Off-hand auto attacks are recorded separately from main-hand swings, which
  combat text cannot express.
- Environmental damage and damage shields are attributed by GUID.
- `docs/NAMPOWER.md`: a full audit of Nampower's event and Lua surface, what
  Skada consumes, what stays on the parser, and what is available but unused.

### Changed

- Overhealing is computed from the healed unit's own GUID on the Nampower path,
  so heals on units that hold no unit token are verified instead of assumed
  fully effective.

### Fixed

- `table.concat`, `unpack`, and `table.foreachi` now read the same length the
  rest of the global compatibility shim already tracks correctly, instead of
  the client's native side-tracked length, which nothing after `table.insert`
  keeps in sync any more. Any table built with the shimmed `table.insert` and
  then handed to one of these came out silently truncated (usually to
  nothing). This broke AceOO's mixin/class identity system used by SuperAPI,
  Nampower's own settings icon, and other Ace2-based addons loaded after
  Skada: their per-class-combination ID string collapsed to `""` for every
  combination, so AceOO's class cache handed back whichever class had been
  cached first instead of the right one -- symptom in the wild: SuperAPI's
  FuBarPlugin-based minimap icon silently missing methods and never showing.
  `string.split`/`strsplit` (bound globally for other addons to call, see
  `core/core.compat.lua`) was itself calling the affected `unpack`.
- The minimap button now uses the same construction every other minimap
  button on this client does (SuperAPI's FuBarPlugin-based icon included):
  the lightning-bolt icon on its own layer with the client's circular
  tracking-border ring drawn as a larger texture on top, instead of a
  backdrop-drawn edge. An earlier same-day fix pushed the button's radius
  out from the conventional 78px to dodge a collision with other addons'
  icons; that turned out to not be a real risk (the actual cause was the
  `table.concat`/`unpack`/`table.foreachi` bug above) and only left a
  visible gap between the button and the minimap, so the radius is back to
  78px, flush with the ring like every other minimap button.

## 2.0.1 - 2026-09-07

### Changed

- The minimap button now shows the client's lightning-bolt spell icon inside
  its circular frame instead of a bare letter.
- The settings dialog wears the default UI's own look instead of a flat
  dark overlay: the untinted dialog-box frame and header ribbon,
  tooltip-bordered inset panes, quest-log row highlights in the sidebar,
  the game's check boxes, dropdowns, input-box border, chat color
  swatches and red panel buttons, with gold captions and white values in
  the client's font objects. The report popup's whisper box shares the
  input-box border, and both dialogs drop the black tint over the frame.
- Bound compatibility sorting to O(n log n) worst-case work, avoiding CPU and
  stack spikes on sorted or equal-valued lists, including other addons' lists.
- Cache discovered list lengths while still detecting external appends and
  removals, avoiding repeated full-list scans in the global compatibility shim.
- Queue unseen or stale group aura baselines on combat roster changes instead
  of scanning the full group synchronously. Fresh caches and immediate pending
  dispel resolution are preserved; queued aura events avoid unused clock reads.
- Add a repeatable host-side benchmark and regression checks for sort cost,
  list-length caching, and combat roster bursts.

### Fixed

- Changing the bar color, bar border color, or "My bar highlight color" now
  repaints the meters immediately instead of waiting for the next toggle or
  page switch to trigger a rebuild.
- The mail window's recipient autocomplete bubble (TurtleMail) no longer
  balloons over the send window or suggests names left over from earlier
  keystrokes: a `table.setn` shrink is now a real truncation, so Lua-5.0-style
  callers that clear and refill a list get one whose tracked length matches
  its contents again.
- Long checkbox and color-swatch labels wrap onto two lines, with taller
  settings rows to keep adjacent controls clear.
- Settings dropdowns now immediately display the saved selection without
  requiring a switch to another settings page and back.

## 2.0.0 - 2026-09-07

### Added

- Healing, HPS, and Healing Targets bars now show the estimated overheal as a
  dimmer continuation of the bar past the effective healing, so a healer's
  bar reads effective + overheal = total cast healing at a glance; the
  tooltip still carries the numbers.

### Changed

- The settings dialog is now Skada's own code, built directly on the client's
  frame APIs. Every slider shows its value as plain text (no type-in box that
  could render blank), the layout is pure arithmetic so controls are correct
  on first open, the select popup menu is Skada-owned and cannot be clipped
  by the scroll pane, and the window-name box feeds its text through a
  one-shot placement driver — no more open/close cycle to see values.
- `core/core.compat.lua` is trimmed to generic shims: stdlib repairs
  (`string.match` probe-and-repair against RollFor's clobber, `string.split`,
  the length-tracking `table.*` functions, `table.sort`), the CreateFrame
  wrapper's client-gap fixes (now `.obj`-gated so BigDebuffs' own bundled
  Ace3 keeps benefiting from them), and the layering helpers. The Ace3-only
  EditBox nudge machinery is gone.
- Settings now follow their actual ownership: every addon-wide behavior,
  appearance, data, and reset control lives under General, while individual
  window pages contain only settings stored by that window. "+ New window" is
  now the first item beneath Windows for immediate access.
- Display rebuilding now uses one tuned 4 Hz cadence, while bars always animate
  smoothly at fixed speed 5. Quiet actor meters stop rebuilding during combat;
  time-dependent views continue updating at the fixed cadence.
- Runtime tickers are coalesced at the shortest registered interval, and bar
  animation visits only windows with visible movement before stopping at a
  subpixel threshold. Stable titles, ranks, and toggle chrome avoid redundant
  client widget updates.
- The report dialog now shares the settings window's classic frame, gold title,
  inset panes, native buttons, typography, fade timing, and window behavior.
- Threat rows now match damage and healing rows: total threat followed by TPS
  and aggro percentage together in parentheses. Ungrouped threat no longer
  sends server queries and displays only the player and owned pets.
- Combat-name normalization uses a pattern-free fast path, repeated unknown
  sources and unresolved target-unit lookups are cached, and fallback threat
  projections reuse row tables instead of reallocating and sorting twice on
  every estimate tick.
- Natural-order combat formats bypass capture remapping, aggregate writes use
  stable hot-path function references, and fallback healing distributes threat
  using an incrementally maintained enemy count.
- Ambient aura changes coalesce by unit and refresh within a bounded per-tick
  budget. Segment start queues only unseen group, target, and focus units,
  keeping uptime segment-scoped without a synchronous roster scan on pull.
- Live duration is sampled once per display rebuild where multiple rows use it,
  and cleared display entries release actor, spell, and segment references so
  reset data is not retained by the UI pool.

### Removed

- The entire vendored Ace3 stack under `libs/` (LibStub, CallbackHandler-1.0,
  AceGUI-3.0, AceConfig-3.0 with Registry/Cmd/Dialog — about 10,400 lines) is
  deleted, along with the Ace3-specific `options/options.sidebar.lua`,
  `options/options.widgets.lua`, `options/options.shell.lua`, and the
  AceGUI ScrollFrame widget shim. The options schema
  (`options/options.schema.lua`) stays as the data contract.
- The update-rate, bar-smoothing, and animation-speed settings and their legacy
  saved values. Display cadence and smooth animation are now tuned internally.

### Fixed

- Mixed positional and automatic localized combat formats now map every capture
  to the correct logical argument instead of silently taking a broken fast path.
- Cached ignored pet sources are reconsidered when a newly observed owner becomes
  trackable, so owner-derived damage is not stranded behind a negative lookup.
- Pending dispel snapshots still resolve while segment recording is inactive,
  and damage needed for a crowd-control break survives a cached unit lookup miss.
- Custom window names remain painted across refreshes and live-mode changes, and
  an all-zero meter uses a safe nonzero paint maximum.
- Group and raid roster detection no longer collapses after a rebuild, and
  segment cycling advances reliably after its choice list is refilled.
- A window whose construction fails mid-build remains inert and visible in the
  settings list instead of erroring on every refresh tick.
- Scrolling immediately after enlarging a window no longer errors; the extra
  rows appear at the next update.
- A trailing bar exactly six pixels tall no longer flickers through floating-
  point rounding in the height calculation.

## 1.2.1 - 2026-09-02

### Changed

- Bordered windows now default to a plain configured-color edge instead of
  the grey outer glow. Existing bordered profiles migrate to solid color;
  soft shadow remains available as an explicit style.

### Fixed

- Mode and fight lists no longer turn blank at the bottom when snap-size has
  preserved the window height as a fractional row count.
- Windows whose height came from a snap-size match or an off-grid resize no
  longer show only their whole rows with an empty band underneath: the
  fractional remainder now paints as a short trailing bar, so the window
  fills to its bottom edge and snapped windows keep their flush alignment.
- The configured window-border color now applies immediately and remains
  stable when a window becomes active; class tinting remains opt-in.
- Borderless windows now remove their backdrop edge instead of making it
  transparent, avoiding a phantom border on clients that ignore edge alpha.
- Meter windows no longer load with phantom settings-selection chrome after
  login or UI reload; selection chrome now appears only while settings are open.
- Window synchronization no longer downgrades the profile migration version
  and reapplies the default border style on every login or UI reload.
- Colored window edges now use dedicated textures, avoiding clients that show
  a grey backdrop edge until the settings window forces another repaint.
- Meter borders are consistently one pixel wide on all four sides, including
  the top edge of the primary window.
- A window whose construction failed part way through no longer appears on
  screen while missing from the settings window list. New windows now
  register before they are built, and a failed build is reported in chat.
- Windows created after deleting one now appear in the settings window list.
  The client's Lua 5.0 table.getn trusts an internal size cache maintained
  by table.remove; a manual append after a delete desynced from that cache
  and hid every later window from getn-based iteration.
- Wiping fight data also resets the client's cached array length for the
  fight history, which wiping alone leaves stale under the same mechanism.
- The settings tree now follows auto-renames immediately: switching a
  window's mode from the meter or through a combat mode switch used to
  leave the tree showing the old name until the panel was reopened.

## 1.2.0 - 2026-09-02

### Added

- Window borders can use the default soft shadow, a plain solid-color edge,
  or no border; the edge color is configurable.

### Changed

- A hidden title bar now also hides access to window actions and automatic
  segment switching from the meter. Those settings remain available through
  `/skada`.
- Right-clicking anywhere in a meter window consistently navigates back,
  including its header controls, resize grip, and empty space.

### Fixed

- Hidden-title windows no longer place an invisible control over their first
  meter row.
- Right-click navigation works when a meter has no bars to display.

## 1.1.0 - 2026-09-02

### Added

- Windows keep their own name once you rename them; auto-named windows now
  take the new mode's name when their mode changes, in the meter and in the
  settings tree.
- Window opacity can now be dragged to 0% for a fully transparent window:
  the row backs and title bar follow the setting along with the backdrop, so
  0% leaves floating bars, text, and buttons. It is now a per-window setting,
  and existing windows keep the value they had. Bar opacity also reaches 0%.
- Per-window "Match size when snapped" setting. When enabled, snapping onto
  another window adopts that target's size along the shared axis only: a
  window dropped beside one matches its height, one dropped above or below
  matches its width.

### Changed

- Windows no longer change size seconds after being dropped next to another
  window. Snap-to-size keeps the adopted size exactly (a partial last row
  just leaves a sliver under the final bar), and moving or resizing a window
  updates its layout right away instead of waiting for the next data rebuild.
- Slider drags follow the cursor even when it leaves the thin slider track,
  and start from anywhere on the slider row.
- Closing the settings window no longer leaves the last-edited meter looking
  selected.
- Window snapping has returned to its original nearest-target behavior. The
  experimental automatic column filling, multi-window corner ownership, and
  fractional height overrides were removed because their competing rules made
  screen-edge and window-edge drops unpredictable.
- Per-window "Hide title bar" setting that collapses the window to its bars;
  the top bar slot then acts as the window's menu bar (right-click opens the
  window menu) and still navigates and drags like the title bar, even when no
  bar is displayed.
- Per-window combat mode switching: a window can switch to a chosen mode when
  combat starts and optionally return to its previous mode when combat ends.
- The window settings are now one scrollable page with Combat, Design, and
  Mode & Segment sections, so every per-window setting is reachable without
  hunting through tabs.
- Windows can now be dragged from any bar or the window background, not only
  the title bar; dragging a bar no longer also opens its detail view.
- Restyled the settings window with the classic dialog frame, gold title
  medallion, and pane-bordered tree and status areas.
- Healing bars now read like damage bars — amount, rate, and share of the
  total ("400 (400, 100.0%)") — instead of a bare number; healing spell
  details and the Healing Targets mode follow the same format.

### Removed

- The per-window "Window scale" setting. It multiplied the whole window on
  top of width, bar height, and font size and fought the snap-size math;
  size windows with width, rows, and bar height instead.

### Fixed

- The window opacity slider visibly changes the meter again: each row paints
  its own dark background, and that layer (with the title bar) did not follow
  the setting.
- With the title bar hidden, the top bar slot reliably receives clicks instead
  of losing them to the first meter bar underneath it.
- Scrolling a settings page no longer draws rows over the page's title and
  description; rows now slide away beneath the header instead.
- The settings scrollbar's thumb now travels the full length of its track:
  the track's height is set explicitly, because a top/bottom-anchored frame
  does not reliably report its resolved height on the 1.12 client.
## 1.0.0 - 2026-09-01

### Added

- Stable Vanilla 1.12.1 and ClassicAPI combat-meter release.
- Damage, healing, threat, mitigation, utility, aura, and death analysis.
- Multiple independently configured meter windows and native settings.
- Automated test validation and tag-driven release packaging.

### Changed

- Organized runtime modules into subsystem directories with qualified
  filenames.
- Split the test suite into ordered domain suites behind a single
  orchestrator with a stubbed environment and shared harness.
- Limited the install archive to runtime files, media, the TOC, and consolidated
  license notices.
- Reworked the interface, threat handling, segment navigation, documentation,
  licensing, and third-party attribution for the PMP release.

### Fixed

- Corrected parser diagnostics, boss targeting, short-segment timing, saved-fight
  selection, mitigation observations, cast targets, reset initialization, aura
  uptime bounds, and periodic callback isolation.
