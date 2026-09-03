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
      local savedLegacyUpdateRate = Skada.db.profile.updateRate
      -- A stale pre-migration key must be inert: the runtime cadence is fixed.
      Skada.db.profile.updateRate = 100

      core.OnUpdate(core, 0.10)
      assert(rebuilds == 0 and animates == 0)

      Skada.dirty = true
      core.OnUpdate(core, 0.25)
      local fixedCadenceWorked = rebuilds == 1 and animates == 0
      Skada.db.profile.updateRate = savedLegacyUpdateRate
      assert(fixedCadenceWorked,
        "legacy updateRate overrode the fixed refresh cadence or unchanged targets animated")

      core.OnUpdate(core, 0.25)
      assert(rebuilds == 1 and animates == 0)

      TestSetTime(301)
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 1 and animates == 0)

      Skada.dirty = true
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 2)
      local row = primary.rows[1]
      assert(row.entry ~= nil)
      local target = row.entry.value
      assert(Skada.UIStyle.BAR_ANIMATION_SPEED == 5 and
        math.abs(Skada.UIStyle.BAR_EASE - 0.165) < 0.000001)
      Skada.db.profile.smoothBars = false
      Skada.db.profile.barSpeed = 1
      row.smoothValue = 0
      primary:Animate()
      assert(row.lastSetValue == row.smoothValue and
        math.abs(row.smoothValue - target * Skada.UIStyle.BAR_EASE) < 0.000001,
        "legacy profile values overrode fixed smooth speed-five animation")
      Skada.db.profile.smoothBars, Skada.db.profile.barSpeed = nil, nil
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

      local baselineQueues, synchronousScans = 0, 0
      local realQueueGroup = Skada.Tracking.QueueGroupBaseline
      local realQueueAura, realScanAll = Skada.Tracking.QueueAuraBaseline, Skada.Tracking.ScanAll
      Skada.Tracking.QueueGroupBaseline = function(self, unknownOnly, now)
        assert(unknownOnly and now == 302)
        baselineQueues = baselineQueues + 1
      end
      Skada.Tracking.QueueAuraBaseline = function(self, unit, unknownOnly, now)
        assert((unit == "target" or unit == "focus") and unknownOnly and now == 302)
        baselineQueues = baselineQueues + 1
      end
      Skada.Tracking.ScanAll = function() synchronousScans = synchronousScans + 1 end
      Skada.Data:StartSegment(302)
      Skada.Tracking.QueueGroupBaseline = realQueueGroup
      Skada.Tracking.QueueAuraBaseline, Skada.Tracking.ScanAll = realQueueAura, realScanAll
      assert(baselineQueues == 3 and synchronousScans == 0,
        "segment start synchronously scanned auras instead of queuing clean baselines")
      primary.db.segment, primary.view, primary.detailActor = "current", "mode", nil
      assert(not Skada.UI:NeedsContinuousRefresh(),
        "raw damage view rebuilt continuously during a quiet combat interval")
      primary.db.mode = "dps"
      assert(not Skada.UI:NeedsContinuousRefresh(),
        "active-time DPS view rebuilt without a new actor event")
      primary.detailActor = "Alice"
      assert(not Skada.UI:NeedsContinuousRefresh(),
        "fixed spell detail values rebuilt continuously")
      primary.db.mode, primary.detailActor, primary.view = "damage", nil, "modes"
      assert(Skada.UI:NeedsContinuousRefresh(), "live mode summaries stopped updating")
      primary.view = "segments"
      assert(Skada.UI:NeedsContinuousRefresh(), "live fight duration stopped updating")
      Skada.Data:EndSegment(303)
      primary.db.mode, primary.db.segment, primary.view = "damage", "current", "mode"
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
