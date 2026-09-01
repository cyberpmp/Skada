"""Suite: render_loop - OnUpdate rebuild-vs-animate contract, trivial segments."""

from harness import Context


def run(ctx: Context):
    ctx.run('''
      TestSetCombat(false)
      Skada.Data:OnCombatLeave(210)
      Skada.Data:Update(212)
      assert(not Skada.Data.active)

      local core = Skada.frame
      local primary = Skada.UI:GetPrimary()
      local rebuilds, animates = 0, 0
      local realRefreshAll, realAnimateAll = Skada.UI.RefreshAll, Skada.UI.AnimateAll
      Skada.UI.RefreshAll = function(self) rebuilds = rebuilds + 1; realRefreshAll(self) end
      Skada.UI.AnimateAll = function(self) animates = animates + 1; realAnimateAll(self) end

      primary.db.visible = true
      primary.view, primary.detailActor, primary.scrollOffset = "mode", nil, 0
      TestSetTime(300)
      Skada.dirty = false
      Skada.UI.animateUntil = 0

      core.OnUpdate(core, 0.10)
      assert(rebuilds == 0 and animates == 0)

      Skada.dirty = true
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 1 and animates == 1)

      core.OnUpdate(core, 0.25)
      assert(rebuilds == 1 and animates == 2)

      TestSetTime(301)
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 1 and animates == 2)

      Skada.dirty = true
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 2)
      local row = primary.rows[1]
      assert(row.entry ~= nil)
      local target = row.entry.value
      row.smoothValue = 0
      primary:Animate()
      assert(row.lastSetValue == row.smoothValue and row.smoothValue > 0 and row.smoothValue < target)
      for _ = 1, 200 do primary:Animate() end
      assert(row.smoothValue == target)

      primary.db.mode = "threat"
      primary.view = "modes"
      assert(not Skada.UI:NeedsContinuousRefresh())
      primary.db.mode = "threat"
      primary.view = "modes"
      assert(not Skada.UI:NeedsContinuousRefresh())
      primary.view = "mode"
      assert(not Skada.UI:NeedsContinuousRefresh())
      TestSetCombat(true)
      assert(Skada.UI:NeedsContinuousRefresh())
      Skada.Threat.lastResponse = nil
      TestSetCombat(false)
      assert(not Skada.UI:NeedsContinuousRefresh())
      Skada.Modes:Set("damage", primary)
    ''')

    ctx.run('''
      local historyCount = table.getn(Skada.Data.history)
      TestSetTime(400)
      Skada.Data:RecordDamage("Alice", "Stray Mob", 7, "Auto Attack", nil, nil, false, 400)
      assert(Skada.Data.active)
      Skada.Data:EndSegment(402)
      assert(not Skada.Data.active)
      assert(table.getn(Skada.Data.history) == historyCount,
        "trivial segment must not consume a history slot")
      Skada.Data:OnCombatEnter(410)
      TestSetTime(411)
      Skada.Data:RecordDamage("Alice", "Boar", 10, "Fireball", 133, nil, false, 411)
      Skada.Data:EndSegment(420)
      assert(table.getn(Skada.Data.history) == historyCount + 1)
    ''')