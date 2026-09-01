"""Suite: debuffs - debuff application and uptime scanning."""

from harness import Context


def run(ctx: Context):
    ctx.run('''
      TestAuras = { target = {} }
      C_UnitAuras = {}
      function C_UnitAuras.UnitAura(unit, index, filter)
        local list = TestAuras[unit]
        if not list then return nil end
        if filter == "HARMFUL|CROWD_CONTROL" then return nil end
        local aura = list[index]
        if not aura then return nil end
        if filter == "HARMFUL" and aura.kind ~= "debuff" then return nil end
        if filter == "HELPFUL" and aura.kind ~= "buff" then return nil end
        return aura.name, nil, 1, "Magic", aura.duration, aura.expiration,
          aura.sourceUnit, nil, nil, aura.spellID
      end
      function C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)
        local list = TestAuras[unit] or {}
        local i
        for i = 1, table.getn(list) do
          local aura = list[i]
          if aura.spellID == spellID then
            return { name = aura.name, spellId = aura.spellID, sourceUnit = aura.sourceUnit, sourceGUID = UnitGUID(aura.sourceUnit) }
          end
        end
      end
      Skada.Tracking.auraAPI = true
      TestAuras.target[1] = { name = "Sunder Armor", spellID = 7386, sourceUnit = "player", duration = 30, expiration = 230, kind = "debuff" }
      Skada.Tracking:ScanAll("target", true, GetTime())
      assert(Skada.Data.current.actors.Alice.debuffs == 1)

      TestSetTime(205)
      TestAuras.target = {}
      Skada.Tracking:ScanAll("target", true, GetTime())
      assert(Skada.Data.current.actors.Alice.debuffUptime == 5, Skada.Data.current.actors.Alice.debuffUptime)
    ''')