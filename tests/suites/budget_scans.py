"""Suite: budget_scans - per-event cost bounds and render cadence.

Locks in the performance invariants behind the raid FPS fixes, without
trading accuracy: a retarget in combat still scans the target silently on
the spot, live-but-quiet window families rebuild at most once per second, the
per-second boss poll stops re-probing the creature API for known targets
(misses included, and across collections), Skada's private getn stays linear
for the `t[table.getn(t) + 1]` append idiom, pet churn folds into one
roster rebuild per data tick, and a dropped damage source is described at
most once per window.
"""

from harness import Context


def run(ctx: Context):
    ctx.run('''
      -- Accuracy first: a plate or retarget in combat scans the unit on the
      -- spot and silently (recordNew=false), so the cache holds what the unit
      -- already wore before any later UNIT_AURA is judged against it. A
      -- queued scan would lag behind genuine aura traffic and miss short CC.
      local savedSegment, savedActive = Skada.Data.current, Skada.Data.active
      TestSetCombat(true)
      Skada.Data:StartSegment(700)
      local scans = {}
      local realScanAll = Skada.Tracking.ScanAll
      Skada.Tracking.ScanAll = function(self, unit, recordNew, now)
        table.insert(scans, { unit = unit, recordNew = recordNew })
        return realScanAll(self, unit, recordNew, now)
      end
      Skada.frame:OnEvent("PLAYER_TARGET_CHANGED")
      assert(table.getn(scans) == 1 and scans[1].unit == "target" and not scans[1].recordNew,
        "a retarget in combat did not scan the target silently on the spot")
      Skada.Tracking.ScanAll = realScanAll
      Skada.Data:EndSegment(705)
      TestSetCombat(false)
      Skada.Data.current = savedSegment
      Skada.Data.active = savedActive
      Skada.Data.noCombatSince = nil
      Skada.Data.nextBossTargetScan = nil
    ''')

    ctx.run('''
      -- Live-but-quiet window families (segments/modes/uptime on the current
      -- fight) are clock-driven at second granularity: their rebuild cadence
      -- must be at most once per second, while the dirty flag still rebuilds
      -- immediately at the 250 ms cadence.
      local savedSegment, savedActive = Skada.Data.current, Skada.Data.active
      TestSetCombat(true)
      Skada.Data:StartSegment(720)
      local primary = Skada.UI:GetPrimary()
      primary.db.visible = true
      primary.db.mode = "damage"
      primary.view = "segments"
      local core = Skada.frame
      local rebuilds, realRefreshAll = 0, Skada.UI.RefreshAll
      Skada.UI.RefreshAll = function(self) rebuilds = rebuilds + 1; realRefreshAll(self) end

      assert(Skada.UI:NeedsContinuousRefresh(720), "segments view must still count as live")
      -- Prime the clock gate deterministically: whatever previous suites left
      -- in it, the first tick at 720.25 is one full second past the prime.
      Skada.RenderPolicy.wallClockCheck = 719
      Skada.dirty = false
      TestSetTime(720.25)
      core.OnUpdate(core, 0.25) -- first live check builds (gate primed at 0)
      assert(rebuilds == 1, "wall-clock view did not build at its first check")
      TestSetTime(720.50)
      core.OnUpdate(core, 0.25)
      TestSetTime(720.75)
      core.OnUpdate(core, 0.25)
      TestSetTime(721.00)
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 1, "wall-clock view rebuilt at the dense cadence: " .. rebuilds)
      TestSetTime(721.25)
      core.OnUpdate(core, 0.25) -- 1 s elapsed -> exactly one more rebuild
      assert(rebuilds == 2, "wall-clock view did not refresh once per second: " .. rebuilds)
      TestSetTime(721.50)
      core.OnUpdate(core, 0.25)
      TestSetTime(721.75)
      core.OnUpdate(core, 0.25)
      TestSetTime(722.00)
      core.OnUpdate(core, 0.25)
      assert(rebuilds == 2, "wall-clock cadence drifted: " .. rebuilds)
      Skada.dirty = true
      TestSetTime(722.25)
      core.OnUpdate(core, 0.25) -- data change still rebuilds immediately
      assert(rebuilds == 3, "the dirty flag no longer rebuilds immediately")
      Skada.UI.RefreshAll = realRefreshAll
      primary.db.mode, primary.db.segment, primary.view = "damage", "current", "mode"
      primary.detailActor, primary.scrollOffset = nil, 0
      Skada.Data:EndSegment(730)
      TestSetCombat(false)
      Skada.Data.current = savedSegment
      Skada.Data.active = savedActive
      Skada.Data.noCombatSince = nil
      Skada.Data.nextBossTargetScan = nil
    ''')

    ctx.run('''
      -- The per-second boss poll must not re-probe the creature API for a
      -- target it has already resolved.
      local savedSegment, savedActive = Skada.Data.current, Skada.Data.active
      local idProbes, infoProbes = 0, 0
      TestSetCombat(true)
      TestSetTarget("Probe Mob", "0xPROBE")
      C_CreatureInfo.GetCreatureID = function() idProbes = idProbes + 1; return 9001 end
      C_CreatureInfo.GetCreatureInfoByID = function() infoProbes = infoProbes + 1; return { rank = 1 } end
      TestSetTime(770)
      Skada.Data:StartSegment(770)
      Skada.Data:Update(770.5)   -- first poll inspects target and probes the API
      Skada.Data:Update(770.9)   -- inside the 1 s throttle: no scan at all
      Skada.Data:Update(771.5)   -- second poll: same GUID -> served from cache
      Skada.Data:Update(772.5)   -- third poll: still cached
      assert(Skada.Data.current.gotboss ~= true, "an elite probe target was misread as a boss")
      assert(idProbes == 1, "creature ID was probed once per poll instead of once per GUID: " .. idProbes)
      assert(infoProbes == 1, "creature info was fetched once per poll instead of once per ID: " .. infoProbes)
      Skada.Data:EndSegment(775)
      TestSetCombat(false)
      TestSetTarget("Boar", "0xC")
      C_CreatureInfo.GetCreatureID = nil
      C_CreatureInfo.GetCreatureInfoByID = nil
      Skada.Data.current = savedSegment
      Skada.Data.active = savedActive
      Skada.Data.noCombatSince = nil
      Skada.Data.nextBossTargetScan = nil
    ''')

    ctx.run(r'''
      -- A GUID without a creature ID is not re-probed, creature info that is
      -- not available yet is asked again, and the info cache survives a
      -- garbage collection.
      local savedSegment, savedActive = Skada.Data.current, Skada.Data.active
      local idProbes, infoProbes = 0, 0
      TestSetCombat(true)
      TestSetTarget("Probe Unknown", "0xPROBEMISS")
      C_CreatureInfo.GetCreatureID = function() idProbes = idProbes + 1; return nil end
      C_CreatureInfo.GetCreatureInfoByID = function() infoProbes = infoProbes + 1; return { rank = 1 } end
      TestSetTime(780)
      Skada.Data:StartSegment(780)
      Skada.Data:Update(780.5)
      Skada.Data:Update(781.5)
      Skada.Data:Update(782.5)
      assert(idProbes == 1, "an unresolvable GUID was re-probed every poll: " .. idProbes)
      assert(infoProbes == 0, "creature info was fetched without a creature ID")

      TestSetTarget("Probe Elite", "0xELITE")
      C_CreatureInfo.GetCreatureID = function() idProbes = idProbes + 1; return 9002 end
      local infoReady = false
      C_CreatureInfo.GetCreatureInfoByID = function()
        infoProbes = infoProbes + 1
        if infoReady then return { rank = 1 } end
      end
      Skada.Data:Update(783.5)
      assert(infoProbes == 1, "creature info was not asked for")
      infoReady = true
      Skada.Data:Update(784.5)
      assert(infoProbes == 2, "creature info that was not available yet was never asked again")
      collectgarbage("collect")
      Skada.Data:Update(785.5)
      assert(infoProbes == 2, "the creature info cache was emptied by a collection: " .. infoProbes)
      Skada.Data:EndSegment(786)
      TestSetCombat(false)
      TestSetTarget("Boar", "0xC")
      C_CreatureInfo.GetCreatureID = nil
      C_CreatureInfo.GetCreatureInfoByID = nil
      Skada.Data.current = savedSegment
      Skada.Data.active = savedActive
      Skada.Data.noCombatSince = nil
      Skada.Data.nextBossTargetScan = nil
    ''')

    ctx.run(r'''
      -- Appending through `t[table.getn(t) + 1] = v` invalidates the length
      -- cache on every append; resuming the scan from the cached length keeps
      -- the build linear. A rescan from index 1 makes 20000 appends cost
      -- ~200 million probes, far past this bound.
      local table = SkadaCompat.Table
      local list = {}
      local started = os.clock()
      local entryIndex
      for entryIndex = 1, 20000 do list[table.getn(list) + 1] = entryIndex end
      assert(table.getn(list) == 20000, "the append idiom lost entries")
      assert(os.clock() - started < 1, "the append idiom is no longer linear")

      -- A cached length whose last entry was cleared rescans and shrinks.
      list[20000] = nil
      assert(table.getn(list) == 19999, "a raw shrink was not picked up")
      table.insert(list, "tail")
      assert(table.getn(list) == 20000 and list[20000] == "tail", "insert after a shrink misplaced the entry")

      -- The private insert takes fixed parameters: on the client every
      -- vararg call builds an argument table.
      assert(not debug.getinfo(table.insert, "u").isvararg,
        "table.insert is a vararg function again; it allocates on every call in game")
      assert(not debug.getinfo(table.insertAt, "u").isvararg,
        "table.insertAt is a vararg function again; it allocates on every call in game")
      local positional = { "a", "c" }
      table.insertAt(positional, 2, "b")
      table.insert(positional, 7)
      assert(positional[1] == "a" and positional[2] == "b" and positional[3] == "c"
        and positional[4] == 7 and table.getn(positional) == 4,
        "insert lost its positional or append form")
      -- A nil value inserts nothing in either form; it never appends the
      -- position as a value.
      local lookup = {}
      table.insertAt(positional, 1, lookup.missing)
      table.insert(positional, lookup.missing)
      assert(table.getn(positional) == 4 and positional[1] == "a",
        "a nil insert changed the list")
    ''')

    ctx.run(r'''
      -- Pet churn: a group member's UNIT_PET only flags a rebuild, a burst of
      -- them folds into one rebuild on the data tick, and other units' pets
      -- are ignored.
      local generation = Skada.Data.rosterGeneration
      Skada.frame:OnEvent("UNIT_PET", "target")
      assert(not Skada.Data.rosterRebuildPending, "a non-group UNIT_PET flagged a rebuild")
      Skada.frame:OnEvent("UNIT_PET", "party1")
      Skada.frame:OnEvent("UNIT_PET", "player")
      Skada.frame:OnEvent("UNIT_PET", "raid12")
      assert(Skada.Data.rosterRebuildPending, "a group UNIT_PET did not flag a rebuild")
      assert(Skada.Data.rosterGeneration == generation, "UNIT_PET rebuilt the roster inline")
      local tickerIndex
      for tickerIndex = 1, table.getn(Skada.tickers) do
        if Skada.tickers[tickerIndex].name == "data" then Skada.tickers[tickerIndex].callback(GetTime()) end
      end
      assert(Skada.Data.rosterGeneration == generation + 1,
        "a burst of pet changes did not fold into exactly one rebuild")
      assert(not Skada.Data.rosterRebuildPending, "the rebuild left its flag set")

      -- A pet summoned onto an empty token attacks at once, so just that pet
      -- is added on the spot and no rebuild follows.
      Skada.Data.rosterRebuildPending = nil
      TestSetUnit("partypet1", { name = "Imp", class = "WARRIOR", guid = "0xI", friend = true, health = 1000, maxHealth = 1000 })
      Skada.frame:OnEvent("UNIT_PET", "party1")
      local imp = Skada.Data.identitiesByName["Imp"]
      assert(imp and imp.owner == "Bob", "a new group pet waited for the data tick")
      assert(Skada.Data.identitiesByGUID["0xI"] == imp, "a new group pet was not keyed by its GUID")
      assert(Skada.Data.rosterGeneration == generation + 2,
        "adding a new pet did not invalidate GUID owner checks")
      assert(not Skada.Data.rosterRebuildPending, "a pet on an empty token still queued a full rebuild")

      -- A second pet wearing a name the roster already holds is added under
      -- its owner's key, not skipped.
      Skada.Data:RebuildRoster()
      TestSetUnit("partypet1", nil)
      Skada.Data:RebuildRoster()
      TestSetUnit("partypet1", { name = "Wolf", class = "WARRIOR", guid = "0xW2", friend = true, health = 1000, maxHealth = 1000 })
      Skada.frame:OnEvent("UNIT_PET", "party1")
      assert(Skada.Data.identitiesByGUID["0xW2"] and Skada.Data.identitiesByGUID["0xW2"].owner == "Bob",
        "a new pet sharing a tracked name waited for the data tick")

      -- A pet leaving or replacing another leaves a stale entry, so it folds
      -- into the tick's rebuild.
      TestSetUnit("partypet1", nil)
      Skada.frame:OnEvent("UNIT_PET", "party1")
      assert(Skada.Data.rosterRebuildPending, "a dismissed pet did not defer its rebuild")

      -- In a raid the roster is built from raid tokens; a party token for the
      -- same member is ignored.
      local realRaidMembers = GetNumRaidMembers
      GetNumRaidMembers = function() return 2 end
      Skada.Data.rosterRebuildPending = nil
      TestSetUnit("partypet1", { name = "Imp", class = "WARRIOR", guid = "0xI", friend = true, health = 1000, maxHealth = 1000 })
      Skada.frame:OnEvent("UNIT_PET", "party1")
      assert(not Skada.Data.identitiesByGUID["0xI"] and not Skada.Data.rosterRebuildPending,
        "a party token's pet event was acted on in a raid")
      GetNumRaidMembers = realRaidMembers
      TestSetUnit("partypet1", nil)
      Skada.Data:RebuildRoster()
    ''')

    ctx.run(r'''
      -- A dropped damage source is described once per window, whatever spell
      -- the next packet from it carries.
      local Nampower = Skada.Nampower
      local notes = Nampower.droppedSources
      local before = table.getn(notes)
      TestSetTime(900)
      Nampower:NoteDroppedSource("0xDROP", "Stray", "Fireball")
      Nampower:NoteDroppedSource("0xDROP", "Stray", "Frostbolt")
      Nampower:NoteDroppedSource("0xDROP", "Stray", "Arcane Missiles")
      local afterBurst = table.getn(notes)
      assert(afterBurst == math.min(before + 1, 5), "a dropped source was described more than once per window")
      TestSetTime(931)
      Nampower:NoteDroppedSource("0xDROP", "Stray", "Fireball")
      assert(notes[table.getn(notes)] and string.find(notes[table.getn(notes)], "Fireball", 1, true),
        "a dropped source was not described again after the window")
    ''')

    ctx.run(r'''
      -- The bounded map drops wholesale at its limit, and its count follows
      -- every add, overwrite and removal.
      local map = Skada.Common.NewBoundedMap(3)
      map:Set("a", 1)
      map:Set("b", false)
      map:Set("a", 2)
      map:Set("b", nil)
      map:Set("missing", nil)
      assert(map.count == 1 and map.entries.a == 2, "the bounded map miscounted its keys")
      map:Set("c", 3)
      map:Set("d", 4)
      map:Set("e", 5)
      assert(map.count == 1 and map.entries.e == 5 and map.entries.a == nil,
        "the bounded map was not dropped at its limit")
      map:Clear()
      assert(map.count == 0 and next(map.entries) == nil, "Clear left entries behind")
    ''')
