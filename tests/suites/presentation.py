"""Suite: presentation - rows, painting, scrolling, navigation, window management."""

from harness import Context


def run(ctx: Context):
    ctx.run('''
      local primary = Skada.UI:GetPrimary()
      primary.view, primary.detailActor, primary.scrollOffset = "mode", nil, 0
      primary:Refresh()
      local first = primary.rows[1]
      assert(first.entry and first.entry.actor.name == "Alice")
      assert(first.textLayer:GetFrameLevel() > first.bar:GetFrameLevel())
      assert(first.left.fontFlags == "OUTLINE" and first.left.fontSize == 15)
      assert(string.find(first.left.textValue, "Alice", 1, true))

      local savedDisplay, savedDisplayCount = primary.display, primary.displayCount
      local savedRows, savedMaximum = primary.db.rows, primary.paintMaximum
      local savedPaintMode, savedPaintSet, savedPaintLive =
        primary.paintMode, primary.paintSet, primary.paintLive
      local synthetic = {}
      local names = { "Bravo", "Alice", "Charlie", "Delta", "Echo", "Foxtrot" }
      local i
      for i = 1, table.getn(names) do
        synthetic[i] = {
          label = names[i], value = 700 - i * 50, text = tostring(700 - i * 50),
          class = "MAGE", actor = { name = names[i], class = "MAGE" },
        }
      end
      primary.display, primary.displayCount = synthetic, table.getn(synthetic)
      primary.db.rows, primary.paintMaximum = 3, synthetic[1].value
      primary.paintLive, primary.detailActor, primary.scrollOffset = false, nil, 0
      primary:PaintRows()
      assert(primary.rows[2].entry == synthetic[2] and not rawget(primary.rows[2], "skadaPinned"))
      primary:Scroll(-1)
      assert(primary.scrollOffset == 1 and primary.rows[1].entry == synthetic[2])
      primary:Scroll(-1)
      assert(primary.scrollOffset == 2)
      assert(primary.rows[1].entry == synthetic[2] and rawget(primary.rows[1], "skadaPinned"))
      assert(primary.rows[1].left.textValue == "2. Alice")
      primary:Scroll(1)
      assert(primary.rows[1].entry == synthetic[2] and not rawget(primary.rows[1], "skadaPinned"))
      primary.detailActor, primary.scrollOffset = "Alice", 2
      primary:PaintRows()
      assert(primary.rows[3].entry == synthetic[5] and not rawget(primary.rows[3], "skadaPinned"))

      primary.display, primary.displayCount = savedDisplay, savedDisplayCount
      primary.db.rows, primary.paintMaximum = savedRows, savedMaximum
      primary.paintMode, primary.paintSet, primary.paintLive =
        savedPaintMode, savedPaintSet, savedPaintLive
      primary.detailActor, primary.scrollOffset = nil, 0
      primary:Refresh()
      first = primary.rows[1]

      C_Spell.GetSpellTexture = function(id) return id == 132 and "IconTest:Fireball" or nil end
      Skada.Data.current.actors.Alice.damageSpells["Fireball"].id = 132
      primary:SelectEntry(first.entry)
      primary:Refresh()
      assert(primary.detailActor == "Alice" and primary.rows[1].entry.spell)
      assert(primary.rows[1].icon.shown and primary.rows[1].icon.texture == "IconTest:Fireball")
      primary:Back()
      primary:Refresh()
      assert(not primary.rows[1].icon.shown and rawget(primary.rows[1], "lastIcon") == nil)

      primary:SelectEntry(first.entry)
      assert(primary.detailActor == "Alice" and primary.view == "mode")
      primary:Back()
      assert(primary.detailActor == nil and primary.view == "mode")
      primary:Back()
      assert(primary.view == "modes")
      primary:Refresh()
      assert(primary.displayCount == table.getn(Skada.Modes.list))

      -- Snap-size may preserve an exact height as a fractional row count.
      -- Pagination must still end on whole table indices or the mode list
      -- becomes blank at its final scroll position.
      local savedModeRows = primary.db.rows
      primary.db.rows = 3.5
      for i = 1, primary.displayCount + 2 do primary:Scroll(-1) end
      local expectedOffset = primary.displayCount - 3
      assert(primary.scrollOffset == expectedOffset and
        primary.scrollOffset == math.floor(primary.scrollOffset),
        "fractional rows produced a fractional final scroll offset")
      assert(primary.rows[1].entry == primary.display[expectedOffset + 1] and
        primary.rows[3].entry == primary.display[primary.displayCount],
        "mode list went blank at its final scroll position")
      primary.db.rows, primary.scrollOffset = savedModeRows, 0
      primary:PaintRows()

      primary:Scroll(-1)
      assert(primary.scrollOffset == 1)
      primary:Back()
      assert(primary.view == "segments" and primary.scrollOffset == 0)
      primary:Refresh()
      assert(primary.display[1].segment == "current")
      assert(primary.display[2].segment == "total")
      primary.header.OnClick(primary.header, "LeftButton")
      assert(primary.view == "modes")
      primary.header.OnClick(primary.header, "LeftButton")
      assert(primary.view == "mode")
      primary.header.OnClick(primary.header, "RightButton")
      assert(primary.view == "modes")
      primary:Back()
      primary:Refresh()
      primary:SelectEntry(primary.display[2])
      assert(primary.db.segment == "total" and primary.view == "modes")
      primary.db.segment = "current"
      primary:SetView("mode")

      primary.db.visible = false
      if primary.frame then primary.frame:Hide() end
      primary.db.visible = true
      if primary.frame then primary.frame:Show() end
      primary.db.x, primary.db.y = 9000, 9000
      SlashCmdList.SKADA("center")
      assert(primary.db.x == 0 and primary.db.y == 0)

      local second = Skada.UI:CreateNew("Healing meter")
      assert(table.getn(Skada.UI.windows) == 2)
      assert(table.getn(Skada.db.profile.windows) == 2)
      assert(second ~= primary and second.frame ~= primary.frame and second.db ~= primary.db)
      Skada.Modes:Set("healing", second)
      second.db.autoSwitch = false
      second.db.segment = "total"

      -- Healing bars carry the overheal as a dimmer continuation past the
      -- effective fill: Bob's 900 cast healing is 400 effective + 500
      -- overheal (combat suite), so the bar scale is the 900 total, the
      -- fill ends at 400/900 of the row and the continuation covers the
      -- remaining 500/900, in the row's colour at reduced alpha.
      second.view, second.detailActor, second.scrollOffset = "mode", nil, 0
      second:Refresh()
      local healRow = second.rows[1]
      assert(healRow.entry and healRow.entry.actor.name == "Bob", "Bob is not the top healer")
      assert(healRow.entry.value == 400 and healRow.entry.extra == 500,
        "healing entry must carry effective as value and overheal as extra")
      assert(second.paintMaximum == 900, "bar scale must cover effective + overheal: " .. tostring(second.paintMaximum))
      local healRowWidth = second.db.width - 2 * Skada.UIStyle.WINDOW_PADDING
      assert(healRow.extra.shown, "overheal continuation must be shown")
      assert(math.abs(healRow.extra.lastPointX - healRowWidth * 400 / 900) < 0.01,
        "continuation must start where the effective fill ends")
      assert(math.abs(rawget(healRow.extra, "width") - healRowWidth * 500 / 900) < 0.01,
        "continuation must span the overheal share of the row")
      assert(healRow.extra.vertexR == healRow.lastR and healRow.extra.alpha < healRow.lastAlpha,
        "continuation must use the bar's colour, dimmed")
      local damageMode = Skada.Modes:Get("damage")
      assert(Skada.Modes:GetActorExtra(damageMode, Skada.Data.current.actors.Bob) == nil,
        "modes without an extraField draw no continuation")
      Skada.Modes:Set("damage", second)
      second:Refresh()
      assert(not second.rows[1].extra.shown, "switching to a mode without extra must hide the continuation")
      Skada.Modes:Set("healing", second)
      second:Refresh()
      Skada.UI:SetActive(second)
      Skada.UI:OnCombatState(true)
      assert(primary.db.segment == "current" and second.db.segment == "total")
      Skada.UI:OnCombatState(false)
      assert(primary.db.segment == "total" and second.db.segment == "total")
      Skada.UI:OnCombatState(true)
      assert(primary.db.segment == "current" and second.db.segment == "total")

      -- per-window combat mode switching: always a round trip
      primary.db.combatMode = "threat"
      local modeBefore = primary.db.mode
      Skada.UI:OnCombatState(true)
      assert(primary.db.mode == "threat" and primary.db.segment == "current",
        "combat enter did not switch to the configured combat mode")
      assert(primary.db.restoreMode == modeBefore, "combat enter did not save the restore mode")
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == modeBefore and primary.db.restoreMode == nil,
        "combat leave did not restore the previous mode")

      -- The way back is saved state: a /reload mid-fight (runtime fields
      -- gone, db.mode already the combat mode) still returns at combat end.
      Skada.UI:OnCombatState(true)
      assert(primary.db.mode == "threat")
      Skada.UI:OnCombatState(true)
      assert(primary.db.restoreMode == modeBefore,
        "a repeated combat enter overwrote the way back with the combat mode")
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == modeBefore, "a reload mid-fight lost the way back")

      -- A window pinned to Overall with automatic segments off comes back
      -- on Overall, though the live combat mode forced Current meanwhile.
      local autoBefore = primary.db.autoSwitch
      primary.db.autoSwitch = false
      primary.db.segment = "total"
      Skada.UI:OnCombatState(true)
      assert(primary.db.segment == "current")
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == modeBefore and primary.db.segment == "total",
        "the combat round trip lost the pinned segment: " .. tostring(primary.db.segment))

      -- A segment picked by hand mid-fight is kept at combat end too (here
      -- on a combat mode that is not live, so the pick sticks meanwhile).
      Skada.Modes:Set(modeBefore, primary)
      primary.db.segment = "total"
      primary.db.combatMode = "healing"
      Skada.UI:OnCombatState(true)
      assert(primary.db.restoreSegment == "total")
      Skada.Data.clientInCombat = true
      primary:ChooseSegment("current")
      Skada.Data.clientInCombat = false
      assert(primary.db.restoreSegment == nil, "a manual segment pick mid-fight kept the way back")
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == modeBefore and primary.db.segment == "current",
        "combat end undid a segment picked by hand: " .. tostring(primary.db.segment))
      primary.db.combatMode = "threat"

      -- A mode picked by hand mid-fight is kept at combat end.
      Skada.UI:OnCombatState(true)
      Skada.Data.clientInCombat = true
      Skada.Modes:Set("healing", primary)
      Skada.Data.clientInCombat = false
      assert(primary.db.restoreMode == nil, "a manual pick mid-fight kept the way back")
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == "healing", "combat end undid a manual pick")
      Skada.Modes:Set(modeBefore, primary)

      -- A window copied mid-fight from one on its combat mode inherits the
      -- way back, so the copy also returns at combat end.
      Skada.UI:OnCombatState(true)
      Skada.UI:SetActive(primary)
      local copy = Skada.UI:CreateNew()
      assert(copy.db.mode == "threat" and copy.db.restoreMode == modeBefore,
        "a window created mid-fight lost the way back")
      Skada.UI:OnCombatState(false)
      assert(copy.db.mode == modeBefore, "a window created mid-fight stayed on the combat mode")
      assert(Skada.UI:DeleteWindow(copy))
      primary.db.autoSwitch = autoBefore

      -- A window already on its combat mode has nothing to restore, and
      -- an empty combat mode is a no-op either way.
      Skada.Modes:Set("threat", primary)
      Skada.UI:OnCombatState(true)
      assert(primary.db.mode == "threat" and primary.db.restoreMode == nil,
        "combat enter must not save a restore mode when already on the combat mode")
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == "threat", "nothing to restore must leave the mode alone")
      primary.db.combatMode = ""
      Skada.UI:OnCombatState(true)
      Skada.UI:OnCombatState(false)
      assert(primary.db.mode == "threat", "empty combat mode must be a no-op")
      Skada.Modes:Set(modeBefore, primary)
      assert(primary.db.mode == modeBefore)
      -- The retired return toggle is dropped from saved profiles, and the
      -- per-window snap values older profiles kept are unified on the
      -- primary's, with the retired gap of 4 turned to 0 once.
      local oldProfile = {
        visualVersion = 6, returnAfterCombat = true, snapDistance = 12, snapGap = 4,
        windows = {
          { returnAfterCombat = false, snapDistance = 20, snapGap = 4 },
          { returnAfterCombat = true, snapDistance = 30, snapGap = 9 },
        },
      }
      Skada.WindowConfig.Migrate(oldProfile)
      assert(oldProfile.returnAfterCombat == nil and oldProfile.windows[1].returnAfterCombat == nil
        and oldProfile.windows[2].returnAfterCombat == nil, "the retired return toggle survived")
      assert(oldProfile.windows[2].snapDistance == 20 and oldProfile.snapDistance == nil,
        "per-window snap distances were not unified on the primary's (and the profile keeps no copy)")
      assert(oldProfile.windows[1].snapGap == 0 and oldProfile.windows[2].snapGap == 0,
        "the retired snap gap of 4 was not migrated")
      -- After the migration a gap of 4 is a choice like any other.
      local chosen = { snapGap = 4 }
      Skada.WindowConfig.ApplyDefaults(chosen, Skada.db.profile)
      assert(chosen.snapGap == 4, "a chosen snap gap of 4 was reset on load")

      assert(Skada.UI:DeleteWindow(second))
      assert(table.getn(Skada.UI.windows) == 1)
      assert(table.getn(Skada.db.profile.windows) == 1)
      Skada.UI:SetActive(primary)
    ''')
