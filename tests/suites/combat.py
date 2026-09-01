"""Suite: combat - combat feed, parser routing, aggregation totals, roster."""

from harness import Context


def run(ctx: Context):
    skada = ctx.skada
    lua = ctx.lua
    parser = skada.Parser

    ctx.set_combat(True)
    skada.Data.OnCombatEnter(skada.Data, 100)
    assert skada.UI.GetPrimary(skada.UI).db.segment == "current"

    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 100.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball crits Boar for 250 Fire damage.")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_PARTY_HITS", "Wolf hits Boar for 40.")
    lua.globals().TestSetUnitHealth("player", 600, 1000)
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_PARTY_BUFF", "Bob's Greater Heal heals Alice for 300.")
    lua.globals().TestSetUnitHealth("player", 900, 1000)
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_PARTY_BUFF", "Bob's Greater Heal critically heals Alice for 600.")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "Boar hits Alice for 50.")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_FRIENDLY_DEATH", "Alice dies.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_SELF_DAMAGE", "You interrupt Boar's Heal.")

    ctx.run('''
      local captured = {}
      Skada.Parser:AddPattern({ "TEST_EVENT" }, "%2$s <- %1$s for %3$d.", function(_, a, b, c)
        captured[1], captured[2], captured[3] = a, b, c
      end)
      Skada.Parser:OnCombatMessage("TEST_EVENT", "Target <- Source for 77.")
      assert(captured[1] == "Source" and captured[2] == "Target" and captured[3] == "77")

      local originalMatch = Skada.Parser.Match
      local matchCount = 0
      Skada.Parser.Match = function(self, entry, message)
        matchCount = matchCount + 1
        return originalMatch(self, entry, message)
      end
      Skada.Parser:AddPattern({ "TEST_CACHED_ROUTE" }, "First %s.", function() end)
      Skada.Parser:AddPattern({ "TEST_CACHED_ROUTE" }, "Second %s.", function() end)
      Skada.Parser:AddPattern({ "TEST_CACHED_ROUTE" }, "Third %s.", function() end)
      Skada.Parser:OnCombatMessage("TEST_CACHED_ROUTE", "Third value.")
      assert(matchCount == 3)
      matchCount = 0
      Skada.Parser:OnCombatMessage("TEST_CACHED_ROUTE", "Third value.")
      assert(matchCount == 1, "repeated parser route did not use its cached format")
      Skada.Parser.Match = originalMatch

      local Tracking = Skada.Tracking
      local originalUnitExists = UnitExists
      UnitExists = function(unit)
        assert(unit ~= "", "empty target was passed to UnitExists")
        return originalUnitExists(unit)
      end
      Tracking:OnSpellSent("player", "", "cast-self", 1459, "Arcane Intellect")
      assert(Tracking.sentCasts["cast-self"])
      Tracking:OnSpellSucceeded("player", "cast-self", 1459, "Arcane Intellect")
      UnitExists = originalUnitExists

      Tracking:OnSpellSent("player", "target", "cast-dispel", 527, "Dispel Magic")
      Tracking:OnSpellSucceeded("player", "cast-dispel", 527, "Dispel Magic")
      Skada.Parser:OnCombatMessage("CHAT_MSG_SPELL_BREAK_AURA", "Boar's Renew is removed.")
    ''')

    current = skada.Data.current
    alice = current.actors["Alice"]
    bob = current.actors["Bob"]

    assert current.damage == 390, current.damage
    assert alice.damage == 390, alice.damage
    assert alice.damageSpells["Fireball"].critical == 1
    assert alice.damageSpells["[Wolf] Auto Attack"].amount == 40
    assert bob.healing == 900, bob.healing
    assert bob.effectiveHealing == 400, bob.effectiveHealing
    assert bob.overhealing == 500, bob.overhealing
    assert bob.healingSpells["Greater Heal"].amount == 900
    assert bob.healingSpells["Greater Heal"].effectiveHealing == 400
    assert bob.healingSpells["Greater Heal"].overhealing == 500
    assert bob.healingSpells["Greater Heal"].count == 2
    assert bob.healingSpells["Greater Heal"].critical == 1
    assert bob.healingSpells["Greater Heal critically"] is None

    misses_before = parser.GetMissCount(parser)
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "unrecognized combat text")
    assert parser.GetMissCount(parser) == misses_before + 1
    lua.globals().SlashCmdList.SKADA("status")
    ctx.run('''
      local savedAddDoubleLine = GameTooltip.AddDoubleLine
      GameTooltip.captured = {}
      GameTooltip.AddDoubleLine = function(self, label, value)
        self.captured[label] = value
      end
      Skada.UIPresenter:ShowEntryTooltip({ entry = {
        label = "Greater Heal",
        spell = Skada.Data.current.actors.Bob.healingSpells["Greater Heal"],
      } })
      assert(GameTooltip.captured.Critical == "1 (50.0%)")
      assert(GameTooltip.captured["Effective (estimated)"] == "400")
      assert(GameTooltip.captured["Overheal (estimated)"] == "500 (55.6%)")
      GameTooltip.captured = {}
      Skada.UIPresenter:ShowEntryTooltip({ entry = {
        label = "Bob",
        actor = Skada.Data.current.actors.Bob,
      } })
      assert(GameTooltip.captured["Effective healing (estimated)"] == "400")
      assert(GameTooltip.captured["Overhealing (estimated)"] == "500")
      local healingMode = Skada.Modes:Get("healing")
      assert(Skada.Modes:GetActorValue(healingMode, Skada.Data.current.actors.Bob) == 400)
      assert(Skada.Modes:GetActorText(healingMode, Skada.Data.current.actors.Bob, Skada.Data.current) == "400")
      assert(Skada.Modes:GetDetailText(healingMode,
        Skada.Data.current.actors.Bob.healingSpells["Greater Heal"],
        Skada.Data.current.actors.Bob, Skada.Data.current) == "400")
      assert(Skada.Modes:GetSetTitle(healingMode, Skada.Data.current) == "400")
      assert(Skada.Modes:GetActorValue(Skada.Modes:Get("overhealing"), Skada.Data.current.actors.Bob) == 500)

      local meter = Skada.UI:GetPrimary()
      meter.db.mode, meter.db.segment, meter.view, meter.detailActor = "healing", "current", "mode", nil
      meter:Refresh()
      assert(meter.display[1].label == "Bob" and meter.display[1].value == 400)
      assert(meter.paintMaximum == 400)
      assert(meter.rows[1].right.textValue == "400")
      assert(not rawget(meter.rows[1], "totalBar"), "standard healing created an overheal bar")
      meter.db.mode = "damage"
      meter:Refresh()
      GameTooltip.AddDoubleLine = savedAddDoubleLine
    ''')
    assert alice.damageTaken == 50, alice.damageTaken
    assert alice.deaths == 1, alice.deaths
    assert alice.interrupts == 1, alice.interrupts
    assert alice.dispels == 1, alice.dispels
    assert skada.Data.total.damage == current.damage
    assert alice.threat is None

    ctx.run('''
      Skada.db.profile.trackAll = true
      assert(Skada.Data:RecordDamage("Charlie", "Boar", 20, "Auto Attack", nil,
        "Physical", false, GetTime()))
      assert(Skada.Data.current.actors.Charlie.damage == 20)
      assert(not Skada.Data.identitiesByName.Charlie.interesting)

      Skada.db.profile.trackAll = false
      assert(not Skada.Data:RecordDamage("Charlie", "Boar", 20, "Auto Attack", nil,
        "Physical", false, GetTime()))
      assert(Skada.Data.current.actors.Charlie.damage == 20)

      local groupedCount = GetNumPartyMembers
      GetNumPartyMembers = function() return 0 end
      Skada.Data:RebuildRoster()
      assert(not Skada.Data.identitiesByName.Bob)

      TestSetTarget("Derek", "0xD")
      Skada.Data:ObserveToken("target")
      assert(Skada.Data.identitiesByName.Derek)
      assert(not Skada.Data.identitiesByName.Derek.interesting)
      assert(not Skada.Data:RecordDamage("Imp (Derek)", "Boar", 25, "Firebolt", nil,
        "Fire", false, GetTime()))
      assert(not Skada.Data.current.actors.Derek)

      assert(not Skada.Data:RecordDamage("Erin", "Boar", 30, "Auto Attack", nil,
        "Physical", false, GetTime()))
      assert(not Skada.Data.current.actors.Erin)

      GetNumPartyMembers = groupedCount
      TestSetTarget("Boar", "0xC")
      Skada.Data:RebuildRoster()
    ''')

    ctx.run('''
      Skada.Data:RecordDamage("Wolf (Alice)", "Boar", 15, "Bite", nil, "Physical", false, GetTime())
      local pet = Skada.Data.current.actors["Alice"]
      assert(pet and pet.damageSpells["[Wolf (Alice)] Bite"], "pet damage not merged to owner")
    ''')