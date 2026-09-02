# Changelog

All notable changes to the PMP Skada rewrite are documented here.

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
- The window settings are now one scrollable page with Combat, Design,
  Text & Color, and Mode & Data sections, so every setting is reachable
  without hunting through tabs.
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
