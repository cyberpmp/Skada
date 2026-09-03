"""Suite: segments - combat history, EndSegment totals, labels, mitigation, deaths."""

from harness import Context


def run(ctx: Context):
    ctx.set_time(120)
    skada = ctx.skada
    skada.Data.Update(skada.Data, 120)
    assert skada.Data.active is True
    assert len(skada.Data.history) == 0

    ctx.set_combat(False)
    skada.Data.OnCombatLeave(skada.Data, 120)
    assert skada.UI.GetPrimary(skada.UI).db.segment == "total"
    skada.Data.Update(skada.Data, 121)
    assert skada.Data.active is True
    skada.Data.Update(skada.Data, 122)
    assert skada.Data.active is False
    assert len(skada.Data.history) == 1

    ctx.run('''
      local historyCount = table.getn(Skada.Data.history)
      local totalHealing = Skada.Data.total.healing
      for tick = 125, 137, 3 do
        TestSetTime(tick)
        assert(not Skada.Data:RecordHealing("Alice", "Alice", 25, "Rejuvenation", 1058, false, tick))
        Skada.Data:Update(tick)
      end
      assert(not Skada.Data.active)
      assert(table.getn(Skada.Data.history) == historyCount)
      assert(Skada.Data.total.healing == totalHealing)
    ''')

    ctx.run('''
      local historyCount = table.getn(Skada.Data.history)
      local totalDamage = Skada.Data.total.damage
      local totalDuration = Skada.Data.total.duration
      Skada.Data:OnCombatEnter(138)
      Skada.Data:RecordDamage("Alice", "Boar", 10, "Fireball", 133, nil, false, 139)
      Skada.Data:EndSegment(141)
      assert(table.getn(Skada.Data.history) == historyCount)
      assert(Skada.Data.total.damage == totalDamage + 10)
      assert(Skada.Data.total.duration == totalDuration + 3)
    ''')

    ctx.run('''
      local previouslySelected = Skada.Data.history[1]
      local primary = Skada.UI:GetPrimary()
      primary.db.autoSwitch = false
      primary.db.segment = 1
      Skada.UI:SyncLegacy(primary)
      Skada.Data:OnCombatEnter(105)
      TestSetTime(111)
      Skada.Data:RecordDamage("Alice", "Boar", 10, "Fireball", 133, nil, false, 111)
      Skada.Data:EndSegment(115)
      assert(primary.db.segment == 2)
      assert(Skada.Data:GetSelectedSet(primary.db.segment) == previouslySelected)

      primary:SetView("segments")
      primary:Refresh()
      assert(primary.display[1].label == "Current")
      assert(primary.display[2].label == "Overall")
      assert(primary.display[3].label == "1. Boar")
      assert(primary.display[4].label == "2. Boar")
      assert(not string.find(primary.display[3].label, "Previous", 1, true))
      assert(Skada.Data:GetSegmentLabel(1) == "1. Boar")
    ''')

    ctx.set_time(200)
    skada.Data.OnCombatEnter(skada.Data, 200)
    current = skada.Data.current

    parser = skada.Parser
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You miss Boar.")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You attack. Boar dodges.")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "Boar attacks. You parry.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_SELF_DAMAGE", "Your Moonfire was resisted by Boar.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "Boar's Rend misses you.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_SELF_MISSES", "You miss Boar.")
    alice = current.actors["Alice"]
    assert alice.misses == 4, alice.misses
    assert alice.avoids == 2, alice.avoids

    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 19. (20 blocked)")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 0. (56 absorbed)")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 8. (glancing)")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 12. (crushing)")
    assert alice.mitigated == 76, alice.mitigated
    assert alice.mitigation.blocked.amount == 20 and alice.mitigation.blocked.count == 1
    assert alice.mitigation.absorbed.amount == 56 and alice.mitigation.absorbed.count == 1
    assert alice.mitigation.glancing.count == 1 and alice.mitigation.crushing.count == 1
    assert alice.damage == 39, alice.damage

    ctx.run('''
      local alice = Skada.Data.current.actors.Alice
      local before = alice.buffUptime or 0
      TestSetTime(202)
      Skada.Data:RecordBuffDuration("Alice", "Pre-combat aura", nil, 30)
      assert(alice.buffUptime == before + 2, alice.buffUptime)
      TestSetTime(200)
    ''')

    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_SELF_BUFF", "You gain 5 Rage from Primal Fury.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_SELF_BUFF", "You gain 10 Mana from Bob's Blessing of Wisdom.")
    assert alice.power == 15, alice.power

    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_SELF_HITS", "You hit Ragnaros for 100.")
    parser.OnCombatMessage(parser, "CHAT_MSG_SPELL_PARTY_BUFF", "Bob's Heal heals Alice for 300.")
    assert alice.damageTargets["Ragnaros"].amount == 100, alice.damageTargets["Ragnaros"].amount
    bob = current.actors["Bob"]
    assert bob.healTargets["Alice"].amount == 300, bob.healTargets["Alice"].amount

    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "Boar hits Alice for 500.")
    parser.OnCombatMessage(parser, "CHAT_MSG_COMBAT_FRIENDLY_DEATH", "Alice dies.")
    assert alice.deaths == 1, alice.deaths
    death = alice.deathLog["death1"]
    assert death.customText == "Killed by Boar (Auto Attack)", death.customText

    ctx.run('''
      -- CycleSegment wipes cycleValues and refills it; under the client's
      -- Lua 5.0 size cache a positional refill would pin table.getn at 0 and
      -- segment cycling would never leave the first choice.
      Skada.db.profile.segment = "current"
      Skada.Data:CycleSegment(1, nil)
      assert(Skada.db.profile.segment == "total",
        "segment cycling did not advance past the first choice: " ..
        tostring(Skada.db.profile.segment))
      Skada.Data:CycleSegment(-1, nil)
      assert(Skada.db.profile.segment == "current",
        "segment cycling did not step back to the first choice: " ..
        tostring(Skada.db.profile.segment))
    ''')