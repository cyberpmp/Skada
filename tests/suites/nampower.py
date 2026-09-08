"""Suite: nampower - server-event ingest, parser suppression, GUID resolution.

Drives Nampower's custom combat events straight into the ingest module's frame
and asserts the aggregates that come out, plus the fact that the chat-text
parser stops producing the same facts while the ingest is active.
"""

from harness import Context


def run(ctx: Context):
    ctx.run(r'''
      local Nampower = Skada.Nampower
      local Parser = Skada.Parser
      local frame = Nampower.frame

      -- Enemies are not on any unit token, so register them the way the client
      -- would expose them: addressable by raw GUID.
      TestRegisterGUIDUnit("0xC", "Boar", "WARRIOR", false, 400, 800)

      -- Probe and activation ------------------------------------------------

      assert(Nampower:Probe(), "probe failed with Nampower and UnitName(guid) both present")
      assert(Nampower.available, "probe did not mark the ingest available")

      Skada.db.profile.useNampower = true
      Nampower:ApplySetting()
      assert(Nampower.active, "ApplySetting did not enable the ingest")
      assert(TestLastCVars.NP_EnableSpellHealEvents == "1",
        "legacy Nampower CVars were not set on enable")

      -- Enabling must silence exactly the parser facts Nampower replaces, and
      -- leave the ones it has no event for alone.
      assert(Parser:IsFactSuppressed("damage"), "damage was not suppressed")
      assert(Parser:IsFactSuppressed("healing"), "healing was not suppressed")
      assert(Parser:IsFactSuppressed("power"), "power was not suppressed")
      assert(Parser:IsFactSuppressed("avoidance"), "avoidance was not suppressed")
      assert(Parser:IsFactSuppressed("dispel"), "dispel was not suppressed")
      assert(Parser:IsFactSuppressed("death"), "death was not suppressed")
      assert(not Parser:IsFactSuppressed("interrupt"),
        "interrupts have no Nampower event and must keep flowing from chat text")

      -- Start a clean fight to assert against, on a known roster: earlier
      -- suites leave the party membership stubs in whatever state they need.
      TestSetPartyMembers(1)
      TestSetTarget("Boar", "0xC")
      Skada.Data:RebuildRoster()
      Skada.Data:Reset()
      TestSetCombat(true)
      Skada.Data:OnCombatEnter(GetTime())

      local function fire(eventName, a, b, c, d, e, f, g, h, i)
        frame:GetScript("OnEvent")(frame, eventName, a, b, c, d, e, f, g, h, i)
      end

      -- Spell damage --------------------------------------------------------

      -- targetGuid, casterGuid, spellId, amount, "absorb,block,resist",
      -- hitInfo, school, "effect1,effect2,effect3,aura"
      fire("SPELL_DAMAGE_EVENT_SELF", "0xC", "0xA", 133, 250, "0,0,0", 0, 2, "2,0,0,0")
      fire("SPELL_DAMAGE_EVENT_SELF", "0xC", "0xA", 116, 400, "0,0,60", 2, 4, "2,0,0,0")

      local current = Skada.Data.current
      local alice = current.actors["Alice"]
      assert(alice, "the caster GUID did not resolve to a named actor")
      assert(alice.damage == 650, "spell damage did not aggregate: " .. tostring(alice.damage))

      local frostbolt = alice.damageSpells["Frostbolt"]
      assert(frostbolt, "the spell ID was not resolved to a name")
      assert(frostbolt.id == 116, "the real spell ID was not carried through")
      assert(frostbolt.critical == 1, "hitInfo bit 2 was not read as a critical")
      assert(alice.mitigation.resisted.amount == 60,
        "the resist component of the mitigation string was dropped")

      -- Enemies never become actors unless trackAll is on, so the enemy shows
      -- up as a damaged-target breakdown row rather than its own bar.
      assert(alice.damageTargets["Boar"].amount == 650,
        "the enemy GUID was not resolved into a damaged-target row")

      -- Damage taken flows the other way: the enemy GUID is the source and the
      -- named group member is the victim.
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xA", "0xC", 8092, 120, "0,0,0", 0, 5, "2,0,0,0")
      assert(alice.damageTaken == 120,
        "damage taken was not attributed to the named victim: " .. tostring(alice.damageTaken))
      assert(alice.takenSpells["Mind Blast"].id == 8092,
        "the incoming spell ID was not carried onto the taken breakdown")

      -- Auto attacks --------------------------------------------------------

      -- attacker, target, damage, hitInfo, victimState, subDamageCount,
      -- blocked, absorbed, resisted
      fire("AUTO_ATTACK_SELF", "0xA", "0xC", 100, 0, 1, 1, 0, 0, 0)
      fire("AUTO_ATTACK_SELF", "0xA", "0xC", 90, 4, 1, 1, 0, 0, 0)
      fire("AUTO_ATTACK_SELF", "0xA", "0xC", 0, 0, 2, 1, 0, 0, 0)
      fire("AUTO_ATTACK_SELF", "0xA", "0xC", 140, 16384, 1, 1, 0, 0, 0)

      assert(alice.damageSpells["Auto Attack"].amount == 240,
        "main-hand swings did not aggregate: " .. tostring(alice.damageSpells["Auto Attack"].amount))
      assert(alice.damageSpells["Auto Attack (Off-Hand)"].amount == 90,
        "the left-swing flag did not split off-hand damage out")
      assert(alice.mitigation.glancing.count == 1, "the glancing flag was not recorded")
      assert(alice.misses == 1, "the dodge victim state was not recorded as a miss for the attacker")

      -- Spell misses --------------------------------------------------------

      fire("SPELL_MISS_SELF", "0xA", "0xC", 116, 2)
      assert(alice.misses == 2, "a resisted spell was not counted as a miss for the caster")
      assert(alice.missSpells["Frostbolt"], "the missed spell name was not recorded")

      -- The avoiding side is credited too, when it is someone Skada tracks.
      fire("SPELL_MISS_OTHER", "0xC", "0xA", 8092, 3)
      assert(alice.avoids == 1, "the player dodging an incoming spell was not credited")
      assert(alice.avoidSpells["Dodge"], "the avoidance type was not recorded")

      -- Healing -------------------------------------------------------------

      -- target, caster, spellId, amount, critical, periodic. Bob heals the
      -- 400/800 Boar-adjacent case: Alice sits at 600/1000 here.
      TestSetUnitHealth("0xA", 600, 1000)
      fire("SPELL_HEAL_BY_OTHER", "0xA", "0xB", 2050, 300, 0, 0)
      local bob = current.actors["Bob"]
      assert(bob and bob.healing == 300, "healing did not aggregate for the healer GUID")
      assert(bob.effectiveHealing == 300 and bob.overhealing == 0,
        "a heal inside the deficit was misread as overheal")

      TestSetUnitHealth("0xA", 900, 1000)
      fire("SPELL_HEAL_BY_OTHER", "0xA", "0xB", 2050, 300, 1, 0)
      assert(bob.effectiveHealing == 400 and bob.overhealing == 200,
        "GUID-exact overheal was not computed: " .. tostring(bob.overhealing))
      assert(bob.healingSpells["Lesser Heal"].critical == 1,
        "the heal critical flag was dropped")

      -- Power ---------------------------------------------------------------

      fire("SPELL_ENERGIZE_BY_SELF", "0xA", "0xA", 8092, 0, 120, 0)
      assert(alice.power == 120, "a mana energize did not aggregate")
      assert(alice.powerSpells["Mind Blast"], "the energize spell name was not resolved")

      -- Environmental damage and damage shields -----------------------------

      local damageBeforeFall = alice.damage
      fire("ENVIRONMENTAL_DMG_SELF", "0xA", 2, 75, 0, 0)
      assert(alice.takenSpells["Falling"].amount == 75,
        "environmental damage was not recorded against the victim")
      assert(alice.damage == damageBeforeFall,
        "environmental damage invented a damage dealer")

      -- A heal on a unit with no resolvable name must still count for the healer
      -- rather than raising on a nil cache key.
      local healingBeforeGhost = bob.healing
      fire("SPELL_HEAL_BY_OTHER", "0xGHOST", "0xB", 2050, 50, 0, 0)
      assert(bob.healing == healingBeforeGhost + 50,
        "a heal on an unresolvable target was dropped")

      fire("DAMAGE_SHIELD_SELF", "0xA", "0xC", 25, 3)
      assert(alice.damageSpells["Reflect (Nature)"].amount == 25,
        "damage shield output was not attributed to the shield owner")

      -- Dispels --------------------------------------------------------------

      fire("SPELL_DISPEL_BY_SELF", "0xA", "0xC", 527)
      assert(alice.dispels == 1, "a dispel was not recorded")
      assert(alice.dispelSpells["Dispel Magic"], "the dispelled spell ID was not named")

      -- Deaths ---------------------------------------------------------------

      fire("UNIT_DIED", "0xA")
      assert(alice.deaths == 1, "a GUID death was not recorded")
      assert(alice.deathLog["death1"], "the death recap entry was not written")

      -- Suppression is real ---------------------------------------------------

      local damageBefore = alice.damage
      local healingBefore = bob.healing
      Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 100.")
      Skada.Parser:OnCombatMessage("CHAT_MSG_SPELL_PARTY_BUFF", "Bob's Greater Heal heals Alice for 300.")
      assert(alice.damage == damageBefore,
        "a chat damage line was double counted while the Nampower ingest was active")
      assert(bob.healing == healingBefore,
        "a chat heal line was double counted while the Nampower ingest was active")

      -- Interrupts have no Nampower event, so the chat route must still fire.
      Skada.Parser:OnCombatMessage("CHAT_MSG_SPELL_SELF_DAMAGE", "You interrupt Boar's Heal.")

      -- Unresolvable GUIDs ----------------------------------------------------

      local unresolvedBefore = Nampower.unresolvedGUIDCount
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xNOPE", "0xALSONOPE", 133, 500, "0,0,0", 0, 2, "2,0,0,0")
      assert(Nampower.unresolvedGUIDCount > unresolvedBefore,
        "an unresolvable GUID was not counted")
      assert(alice.damage == damageBefore,
        "an unresolvable GUID pair leaked into an existing actor")

      -- Disabling restores the chat path ---------------------------------------

      Skada.db.profile.useNampower = false
      Nampower:ApplySetting()
      assert(not Nampower.active, "ApplySetting did not disable the ingest")
      assert(not Parser:IsFactSuppressed("damage"),
        "disabling the ingest did not hand damage back to the parser")

      Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 100.")
      assert(alice.damage == damageBefore + 100,
        "the chat parser did not resume after the ingest was disabled")

      -- Events arriving while inactive must be ignored outright.
      fire("SPELL_DAMAGE_EVENT_SELF", "0xC", "0xA", 133, 999, "0,0,0", 0, 2, "2,0,0,0")
      assert(alice.damage == damageBefore + 100,
        "the ingest recorded an event after being disabled")

      -- Absent Nampower ---------------------------------------------------------

      TestSetNampowerPresent(false)
      Nampower.available = false
      assert(not Nampower:Probe(), "probe succeeded without GetNampowerVersion")
      assert(Nampower.reason == "Nampower not loaded", "probe reported the wrong reason")
      Skada.db.profile.useNampower = true
      Nampower:ApplySetting()
      assert(not Nampower.active, "the ingest activated without Nampower loaded")
      assert(not Parser:IsFactSuppressed("damage"),
        "the parser stayed suppressed with no ingest to replace it")

      TestSetNampowerPresent(true)
      Nampower:Probe()
      Skada.db.profile.useNampower = false
      Nampower:ApplySetting()

      TestSetCombat(false)
      Skada.Data:Reset()
    ''')
