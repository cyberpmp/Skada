"""Suite: auras - crowd-control tracking and CC breaks."""

from harness import Context


def run(ctx: Context):
    ctx.run('''
      TestAuras = { target = {} }
      C_UnitAuras = {}
      function C_UnitAuras.UnitAura(unit, index, filter)
        local aura = TestAuras[unit] and TestAuras[unit][index]
        if not aura then return nil end
        return aura.name, nil, 1, "Magic", aura.duration, aura.expiration,
          aura.sourceUnit, nil, nil, aura.spellID
      end
      function C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)
        local list = TestAuras[unit] or {}
        for i = 1, table.getn(list) do
          local aura = list[i]
          if aura.spellID == spellID then
            return {
              name = aura.name,
              spellId = aura.spellID,
              sourceUnit = aura.sourceUnit,
              sourceGUID = UnitGUID(aura.sourceUnit),
            }
          end
        end
      end
      Skada.Tracking.auraAPI = true
      Skada.Tracking:ScanCC("target", false, GetTime())
      TestAuras.target[1] = {
        name = "Polymorph", spellID = 118, sourceUnit = "player",
        duration = 20, expiration = 120,
      }
      Skada.Tracking:OnUnitAura("target")
      Skada.Tracking:DrainDirtyAuras(GetTime(), 4)
      assert(Skada.Data.current.actors.Alice.cc == 1)

      TestSetTime(105)
      Skada.Tracking.unitMissByName.Boar = 104.9
      Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_PARTY_HITS", "Bob hits Boar for 5.")
      TestAuras.target = {}
      Skada.Tracking:OnUnitAura("target")
      Skada.Tracking:DrainDirtyAuras(GetTime(), 4)
      assert(Skada.Data.current.actors.Bob.ccBreaks == 1)
      assert(Skada.Data.current.actors.Alice.ccDuration == 5)

      local realUnitAura = C_UnitAuras.UnitAura
      local auraReads = 0
      C_UnitAuras.UnitAura = function(unit, index, filter)
        auraReads = auraReads + 1
        return realUnitAura(unit, index, filter)
      end
      local wasActive = Skada.Data.active
      local pending = { targetUnit = "target" }
      table.insert(Skada.Tracking.pendingDispels, pending)
      local realResolve = Skada.Tracking.ResolveDispelSnapshot
      local pendingResolved = 0
      Skada.Tracking.ResolveDispelSnapshot = function(self, candidate, now)
        if candidate == pending then pendingResolved = pendingResolved + 1; return true end
        return realResolve(self, candidate, now)
      end
      local queuedBefore = table.getn(Skada.Tracking.pendingAuraBaselines)
      Skada.Data.active = false
      Skada.Tracking:OnUnitAura("target")
      Skada.Tracking:OnUnitAura("target")
      local ambientReads = auraReads
      local queuedAfter = table.getn(Skada.Tracking.pendingAuraBaselines)
      Skada.Data.active = wasActive
      C_UnitAuras.UnitAura = realUnitAura
      Skada.Tracking.ResolveDispelSnapshot = realResolve
      assert(ambientReads == 0, "ambient UNIT_AURA scanned full aura lists instead of queuing one baseline")
      assert(queuedAfter == queuedBefore + 1,
        "repeated ambient UNIT_AURA events were not coalesced by unit")
      assert(pendingResolved == 1,
        "inactive UNIT_AURA discarded a pending dispel instead of resolving its snapshot")

      local realScanAll = Skada.Tracking.ScanAll
      local baselineScans = 0
      Skada.Tracking.ScanAll = function(self, unit, recordNew, now)
        baselineScans = baselineScans + 1
        assert(unit == "target" and not recordNew)
        return realScanAll(self, unit, recordNew, now)
      end
      Skada.Tracking:DrainAuraBaselines(GetTime(), 1)
      Skada.Tracking.ScanAll = realScanAll
      assert(baselineScans == 1,
        "queued ambient aura baseline was skipped or exceeded its per-tick budget")
    ''')
