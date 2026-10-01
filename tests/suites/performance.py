"""Suite: performance - retained memory, sort cost, and combat aura bursts."""

from itertools import permutations
from random import Random

from harness import Context, load_addon


def run(ctx: Context):
    retained_kb = ctx.eval('''
      function()
        collectgarbage("collect")
        local before = collectgarbage("count")
        for i = 1, 50000 do
          Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 1.")
        end
        collectgarbage("collect")
        return collectgarbage("count") - before
      end
    ''')()
    assert retained_kb < 256, retained_kb

    ctx.run('''
      local retainedActor = { name = "Old actor" }
      local retainedEntry = { label = "Old actor", actor = retainedActor }
      local displayOwner = { display = { retainedEntry } }
      Skada.UIPresenter.ClearDisplay(displayOwner)
      assert(retainedEntry.actor == nil and retainedEntry.label == nil,
        "display pool retained an actor after the visible entry was cleared")

      local realUnitExists = UnitExists
      local lookups = 0
      UnitExists = function(unit)
        lookups = lookups + 1
        return realUnitExists(unit)
      end
      Skada.Tracking.unitMissByName = {}
      Skada.Tracking:NoteDamage("Alice", "Unseen Performance Target", "Fireball", 1000)
      local firstLookupCount = lookups
      assert(firstLookupCount > 0)
      for i = 1, 100 do
        Skada.Tracking:NoteDamage("Alice", "Unseen Performance Target", "Fireball", 1000.1)
      end
      assert(lookups == firstLookupCount,
        "unresolved damage target repeated its unit-token scan per event")
      Skada.Tracking:NoteDamage("Alice", "Unseen Performance Target", "Fireball", 1000.6)
      assert(lookups > firstLookupCount, "unresolved damage target was never retried")
      UnitExists = realUnitExists
    ''')

    # Isolate synthetic raid events from the stateful combat suites.
    isolated = Context(*load_addon())
    isolated.run('''
      for order = 1, 4 do
        local values, comparisons = {}, 0
        for i = 1, 256 do
          if order == 1 then values[i] = i
          elseif order == 2 then values[i] = 257 - i
          elseif order == 3 then values[i] = 1
          else values[i] = i * 37 - math.floor(i * 37 / 256) * 256 end
        end
        table.sort(values, function(a, b)
          comparisons = comparisons + 1
          return a < b
        end)
        for i = 2, 256 do assert(values[i - 1] <= values[i]) end
        assert(comparisons < 8192, "sort cost became quadratic: " .. comparisons)
        if order < 3 then
          for i = 1, 256 do assert(values[i] == i, "sort lost an entry") end
        end
      end
      local values = { { value = 3 }, { value = 1 }, { value = 2 } }
      table.sort(values, function(a, b) return a.value > b.value end)
      assert(values[1].value == 3 and values[2].value == 2 and values[3].value == 1)
      Skada.Common.Wipe(values)
      table.sort(values)
      table.insert(values, 7)
      table.sort(values)
      assert(table.getn(values) == 1 and values[1] == 7)

      -- Large duplicate and organ-pipe inputs exercise hostile partitions.
      for order = 1, 2 do
        local values, comparisons = {}, 0
        for i = 1, 4096 do
          values[i] = order == 1 and math.min(i, 4097 - i) or 1
        end
        table.sort(values, function(a, b)
          comparisons = comparisons + 1
          return a < b
        end)
        assert(comparisons < 4096 * 100, "hostile sort input exceeded work bound")
        for i = 2, 4096 do assert(values[i - 1] <= values[i]) end
      end

      -- The length shim self-heals against native-style mutation (a
      -- `t[n + 1] = v` append or a `t[n] = nil` trim that the tracked size
      -- never saw) while staying raw like the native library: a table's
      -- __index is never consulted, so a proxy or strict table (Bagshui's
      -- rule item table asserts on any miss) is safe to measure.
      local externalList = {}
      local fillIndex
      for fillIndex = 1, 512 do externalList[fillIndex] = fillIndex end
      assert(table.getn(externalList) == 512)
      externalList[513] = 513
      assert(table.getn(externalList) == 513, "cached length missed a native-style append")
      externalList[513] = nil
      externalList[512] = nil
      assert(table.getn(externalList) == 511, "cached length missed a native-style trim")
      local probed = false
      local proxied = setmetatable({}, { __index = function() probed = true end })
      assert(table.getn(proxied) == 0 and not probed,
        "the length shim must not read through __index (the native library is raw)")

      -- The cached length must actually be used: an unchanged list is not
      -- rescanned per read, and a list built or drained through
      -- insert/remove is not rescanned per call (that was quadratic for
      -- every addon in the client). Counted in VM instructions, which a
      -- rescan of 4000 entries per call would multiply by thousands.
      if debug and debug.sethook then
        local function instructions(work)
          local ticks = 0
          debug.sethook(function() ticks = ticks + 1 end, "", 100)
          work()
          debug.sethook()
          return ticks * 100
        end
        local built = {}
        local cost = instructions(function()
          local itemIndex
          for itemIndex = 1, 4000 do table.insert(built, itemIndex) end
        end)
        assert(table.getn(built) == 4000)
        assert(cost < 4000 * 200, "table.insert rescanned the list per call: " .. cost)
        cost = instructions(function()
          local readIndex
          for readIndex = 1, 4000 do assert(table.getn(built) == 4000) end
        end)
        assert(cost < 4000 * 100, "an unchanged list was rescanned per length read: " .. cost)
        cost = instructions(function()
          while table.getn(built) > 0 do table.remove(built) end
        end)
        assert(built[1] == nil, "draining lost track of the list")
        assert(cost < 4000 * 200, "table.remove rescanned the list per call: " .. cost)
      end

      -- Sort is raw and bounded like native auxsort: a comparator that is
      -- not a strict order must raise, not run the partition scan off the
      -- end of the range forever (through __index or nil-tolerant compares).
      local padded = setmetatable({}, { __index = function() return 0 end })
      local padIndex
      for padIndex = 1, 20 do rawset(padded, padIndex, 5) end
      local sorted, sortError = pcall(table.sort, padded, function(a, b) return a <= b end)
      assert(not sorted and string.find(tostring(sortError), "invalid order function", 1, true),
        "a non-strict comparator did not raise: " .. tostring(sortError))

      -- A setn shrink is a length contract for Lua-5.0-style callers:
      -- TurtleMail's mail recipient autocomplete clears its suggestion list
      -- with setn(0), refills it with table.insert, then setn-truncates it
      -- to the popup's button count while the table still physically holds
      -- every candidate. If the tail survived, the next length read answered
      -- with the physical count -- stale entries at the front, fresh inserts
      -- behind them, and the popup balloon sized from every match on the
      -- realm -- which covered the send window and suggested old names.
      local suggestions = {}
      local refillIndex
      for refillIndex = 1, 3 do table.insert(suggestions, "old" .. refillIndex) end
      table.setn(suggestions, 0)
      assert(suggestions[1] == nil, "a setn shrink left stale entries behind")
      for refillIndex = 1, 200 do table.insert(suggestions, "match" .. refillIndex) end
      table.setn(suggestions, math.min(table.getn(suggestions), 8))
      assert(table.getn(suggestions) == 8, "setn truncation did not stick")
      assert(suggestions[9] == nil, "a truncated list kept its tail")
      assert(suggestions[1] == "match1", "a refilled list resumed after a stale tail")
    ''')

    sort_values = isolated.eval('''function(values, descending)
      if descending then table.sort(values, function(a, b) return a > b end)
      else table.sort(values) end
      return values
    end''')
    rng = Random(42)
    cases = list(permutations(range(6)))
    cases.extend([rng.randrange(20) for _ in range(size)] for size in (13, 14, 40, 128, 513))
    for values in cases:
        for descending in (False, True):
            actual = sort_values(isolated.lua.table_from(values), descending)
            assert list(actual.values()) == sorted(values, reverse=descending)

    isolated.run('''
      local tracking = Skada.Tracking
      tracking.auraAPI = true
      Skada.Data.active = true
      local scans, clockReads = 0, 0
      local realGetTime = GetTime
      GetTime = function() clockReads = clockReads + 1; return realGetTime() end
      tracking.ScanAll = function(self, unit, recordNew)
        scans = scans + 1
        assert(not recordNew, "roster baseline counted existing auras as applications")
        self.pendingAuraBaselineUnits[unit] = nil
      end
      for i = 1, 100 do tracking:OnUnitAura("player") end
      assert(clockReads == 0, "queued aura events read the clock without a pending dispel")
      assert(table.getn(tracking.dirtyAuraQueue) == 1)
      tracking.pendingDispels = { { targetUnit = "player" } }
      local resolved = false
      tracking.ResolveDispelSnapshot = function(self, pending, now)
        assert(pending.targetUnit == "player" and now == realGetTime())
        resolved = true
        return true
      end
      tracking:OnUnitAura("player")
      assert(resolved and table.getn(tracking.pendingDispels) == 0,
        "combat aura queue delayed a pending dispel")
      Skada.Common.Wipe(tracking.dirtyAuraQueue)
      Skada.Common.Wipe(tracking.dirtyAuraUnits)

      local realExists, realName, realGUID = UnitExists, UnitName, UnitGUID
      GetNumRaidMembers = function() return 40 end
      UnitExists = function(unit)
        return string.find(unit, "^raid%d+$") ~= nil or realExists(unit)
      end
      UnitName = function(unit)
        if string.find(unit, "^raid%d+$") then return "Member " .. unit end
        return realName(unit)
      end
      UnitGUID = function(unit)
        if string.find(unit, "^raid%d+$") then return "GUID " .. unit end
        return realGUID(unit)
      end
      tracking.auraCacheSeen["GUID raid1"] = GetTime()
      tracking.auraCacheSeen["GUID raid2"] = GetTime() - 121
      for i = 1, 20 do
        Skada.frame.OnEvent(Skada.frame, "RAID_ROSTER_UPDATE")
      end
      assert(scans == 0, "roster events synchronously scanned auras during combat")
      assert(table.getn(tracking.pendingAuraBaselines) == 41,
        "roster burst failed to coalesce unseen or stale group baselines")
      assert(not tracking.pendingAuraBaselineUnits.raid1,
        "roster change queued a baseline over a fresh combat aura cache")
      assert(tracking.pendingAuraBaselineUnits.raid2,
        "roster change failed to refresh an expired baseline")
      tracking:DrainAuraBaselines(GetTime(), 1)
      assert(scans == 1, "roster baseline exceeded the per-tick scan budget")
      for i = 1, 40 do tracking:DrainAuraBaselines(GetTime(), 1) end
      assert(scans == 41 and table.getn(tracking.pendingAuraBaselines) == 0,
        "queued roster baseline lost a unit")
    ''')
