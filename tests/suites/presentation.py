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
      Skada.UI:SyncLegacy(primary)
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
      Skada.UI:SetActive(second)
      Skada.UI:OnCombatState(true)
      assert(primary.db.segment == "current" and second.db.segment == "total")
      Skada.UI:OnCombatState(false)
      assert(primary.db.segment == "total" and second.db.segment == "total")
      Skada.UI:OnCombatState(true)
      assert(primary.db.segment == "current" and second.db.segment == "total")
      assert(Skada.UI:DeleteWindow(second))
      assert(table.getn(Skada.UI.windows) == 1)
      assert(table.getn(Skada.db.profile.windows) == 1)
      Skada.UI:SetActive(primary)
    ''')