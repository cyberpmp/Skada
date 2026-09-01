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
      assert(Skada.Data.current.actors.Alice.cc == 1)

      TestSetTime(105)
      Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_PARTY_HITS", "Bob hits Boar for 5.")
      TestAuras.target = {}
      Skada.Tracking:OnUnitAura("target")
      assert(Skada.Data.current.actors.Bob.ccBreaks == 1)
      assert(Skada.Data.current.actors.Alice.ccDuration == 5)
    ''')