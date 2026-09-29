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

      -- The packet's exact target GUID reaches the threat estimator, so a hit
      -- on an untargeted twin never lands on the targeted one. The player is
      -- targeting 0xC while Bob hits a second Boar, 0xD.
      TestRegisterGUIDUnit("0xD", "Boar", "WARRIOR", false, 400, 800)
      local estimator = Skada.ThreatEstimate
      estimator:Reset()
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xD", "0xB", 133, 500, "0,0,0", 0, 2, "2,0,0,0")
      assert(estimator.threatByEnemyKey["0xD"] and estimator.threatByEnemyKey["0xD"].Bob,
        "Nampower damage on the untargeted twin did not key by its GUID")
      assert(not estimator.threatByEnemyKey["0xC"],
        "Nampower damage on the untargeted twin landed on the targeted mob")
      -- The death packet drops exactly that mob, whatever the target says.
      fire("UNIT_DIED", "0xD")
      assert(not estimator.threatByEnemyKey["0xD"] and not estimator.enemyByKey["0xD"],
        "a Nampower death packet did not remove the fallen mob by GUID")
      estimator:Reset()

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

      -- The aura-snapshot route (a buff missing from the target after the
      -- cast) must stay silent while the packet is authoritative, or the
      -- same dispel is counted once by each. Drive the snapshot path the way
      -- a real cast does and fake the target's auras vanishing.
      local Tracking = Skada.Tracking
      local savedSnapshot = Tracking.SnapshotAuras
      local auraGone = false
      Tracking.SnapshotAuras = function() if auraGone then return {} end return { [8092] = "Mind Blast" } end
      Tracking:OnSpellSent("player", "target", "cast-dispel-np", 527, "Dispel Magic")
      Tracking:OnSpellSucceeded("player", "cast-dispel-np", 527, "Dispel Magic")
      assert(table.getn(Tracking.pendingDispels) == 0,
        "a pending snapshot dispel was opened while Nampower owns dispels")
      fire("SPELL_DISPEL_BY_SELF", "0xA", "0xC", 8092)
      auraGone = true
      Tracking:OnUnitAura("target")
      Tracking.SnapshotAuras = savedSnapshot
      assert(alice.dispels == 2, "a dispel was counted twice under Nampower: " .. tostring(alice.dispels))

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
      -- A caster the client cannot name (a stranger's summon, an unseen
      -- unit) hitting a known target must not be credited to the player.
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xNOPE", 22703, 255, "0,0,0", 0, 2, "2,0,0,0")
      assert(alice.damage == damageBefore,
        "an unnamed caster's damage was credited to the player")

      -- The dropped hit is noted for /skada status with everything the client
      -- could say about the source, so a player's report shows why.
      local lastNote = Nampower.droppedSources[table.getn(Nampower.droppedSources)]
      assert(lastNote and string.find(lastNote, "0xNOPE", 1, true) and string.find(lastNote, "live no", 1, true),
        "an uncredited source was not noted for status: " .. tostring(lastNote))
      assert(string.find(lastNote, "byGUID absent", 1, true) and string.find(lastNote, "tries 0", 1, true),
        "the note does not describe the registry's view of the source: " .. lastNote)
      assert(string.find(Nampower:GetStatusText(), "build test-build", 1, true),
        "status does not name the build stamp")

      -- Summons -----------------------------------------------------------------

      -- A Fire Nova Totem casts once and despawns before its damage packets
      -- are read. The SPELL_GO that precedes them is the only moment the
      -- client can still name the totem and its summoner, so the ingest must
      -- learn the owner there and credit the hits afterwards.
      TestRegisterGUIDUnit("0xT1", "Fire Nova Totem IV", "WARRIOR", true, 5, 5)
      TestSetUnitSummoner("0xT1", "0xA")
      fire("SPELL_GO_OTHER", 0, 11970, "0xT1", "0x0000000000000000", 0, 3, 0)
      TestUnregisterGUIDUnit("0xT1")
      assert(UnitName("0xT1") == nil, "the despawned totem is still resolvable")
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT1", 11970, 180, "0,0,0", 0, 4, "2,0,0,0")
      assert(alice.damage == damageBefore + 180,
        "the player's totem damage was not merged into the player: " .. tostring(alice.damage))
      local totemSpell = alice.damageSpells["[Fire Nova Totem IV] Fire Nova"]
      assert(totemSpell and totemSpell.amount == 180,
        "totem damage was not listed under the totem's name on the owner")
      damageBefore = alice.damage

      -- Mobs attack totems, so a totem is often on a unit token
      -- ("targettarget") and filed by the token observer as a plain unit
      -- before any of its packets arrive. In the field every nova was dropped
      -- this way while status printed "live yes, owner <player> (in group)".
      TestSetTarget("Fire Nova Totem VI", "0xT6")
      TestSetUnitSummoner("0xT6", "0xA")
      Skada.Data:ObserveToken("target")
      local observed = Skada.Data:GetIdentityByGUID("0xT6")
      assert(observed and not observed.interesting, "the observed totem should start as a plain unit")
      TestSetTarget("Boar", "0xC")
      TestRegisterGUIDUnit("0xT6", "Fire Nova Totem VI", "WARRIOR", true, 5, 5)
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT6", 11970, 75, "0,0,0", 0, 4, "2,0,0,0")
      assert(alice.damage == damageBefore + 75,
        "a totem already observed on a token was never adopted: " .. tostring(alice.damage))
      assert(alice.damageSpells["[Fire Nova Totem VI] Fire Nova"],
        "the token-observed totem was not merged under its name")
      damageBefore = alice.damage

      -- The owner field can be empty on the very first packet that names a
      -- fresh totem and readable a moment later. That first miss must not be
      -- remembered for the totem's life: in the field, "live yes, owner
      -- <player> (in group)" was printed for hits that were still dropped.
      TestRegisterGUIDUnit("0xT5", "Fire Nova Totem V", "WARRIOR", true, 5, 5)
      fire("SPELL_GO_OTHER", 0, 11970, "0xT5", "0x0000000000000000", 0, 3, 0)
      TestSetUnitSummoner("0xT5", "0xA")
      -- The nova lands in the same instant as its spell-go.
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT5", 11970, 60, "0,0,0", 0, 4, "2,0,0,0")
      assert(alice.damage == damageBefore + 60,
        "an owner field that missed at spell-go was not re-read on the damage packet: " .. tostring(alice.damage))
      damageBefore = alice.damage

      -- An ordinary mob with no summoner is re-read a few times, then held
      -- for a while rather than read on every hit.
      local savedField = GetUnitField
      local fieldReads = 0
      GetUnitField = function(unit, fieldName) fieldReads = fieldReads + 1 return savedField(unit, fieldName) end
      TestRegisterGUIDUnit("0xM", "Wolf Pup", "WARRIOR", false, 100, 100)
      local hitIndex
      for hitIndex = 1, 6 do
        fire("SPELL_DAMAGE_EVENT_OTHER", "0xA", "0xM", 8092, 1, "0,0,0", 0, 5, "2,0,0,0")
      end
      GetUnitField = savedField
      assert(fieldReads == 6, "a summoner miss was held before three retries: " .. fieldReads)
      TestSetUnitHealth("0xA", 1000, 1000)

      -- The client may never name the totem at all, neither at spell-go nor
      -- at damage time. The player's own spell-go for "Fire Nova Totem" then
      -- vouches for an unnamed caster dealing "Fire Nova" shortly after.
      fire("SPELL_GO_SELF", 0, 1535, "0xA", "0x0000000000000000", 0, 0, 0)
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xGHOST", 11970, 90, "0,0,0", 0, 4, "2,0,0,0")
      assert(alice.damage == damageBefore + 90,
        "an unnamed totem's nova after the player's own totem cast was not credited: " .. tostring(alice.damage))
      assert(alice.damageSpells["[Fire Nova Totem] Fire Nova"],
        "the vouched-for nova was not listed under the totem the player cast")
      damageBefore = alice.damage
      -- The vouching expires: an unnamed nova long after the cast stays dropped.
      TestSetTime(GetTime() + 30)
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xGHOST2", 11970, 90, "0,0,0", 0, 4, "2,0,0,0")
      assert(alice.damage == damageBefore, "a stale totem cast vouched for an unnamed caster")

      -- A summon is a source only. Mobs hitting the totem, missing it, or
      -- the totem exploding must not give it rows of its own or count
      -- against the owner as damage taken, avoids or deaths.
      local deathsBefore, avoidsBefore, takenBefore = alice.deaths, alice.avoids, alice.damageTaken
      TestRegisterGUIDUnit("0xT1", "Fire Nova Totem IV", "WARRIOR", true, 5, 5)
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xT1", "0xC", 8092, 5, "0,0,0", 0, 5, "2,0,0,0")
      fire("SPELL_MISS_OTHER", "0xC", "0xT1", 8092, 3)
      fire("UNIT_DIED", "0xT1")
      assert(not current.actors["Fire Nova Totem IV"], "a summon got actor rows as a target")
      assert(alice.deaths == deathsBefore, "a summon's death counted for the owner")
      assert(alice.avoids == avoidsBefore, "a summon's dodge counted for the owner")
      assert(alice.damageTaken == takenBefore, "a summon's damage taken counted for the owner: " .. tostring(alice.damageTaken))
      assert(Skada.Data:IsSummon("Fire Nova Totem IV") and not Skada.Data:IsSummon("Alice"),
        "IsSummon does not tell summons from players")

      -- Spell-go reaches the threat estimator only through the ingest's own
      -- frame and the bus. The shared frame refuses Nampower codes, so a
      -- direct registration would be dead in game.
      assert(not Skada.eventHandlers["SPELL_GO_SELF"] and not Skada.eventHandlers["SPELL_GO_OTHER"]
        and not Skada.eventHandlers["UNIT_DIED"],
        "a Nampower event is registered on the shared frame, where it never fires")
      local spellGoSeen
      Skada:Subscribe("spellGo", function(spellID, casterGUID, targetGUID, targetsHit)
        spellGoSeen = { spellID, casterGUID, targetGUID, targetsHit }
      end)
      fire("SPELL_GO_SELF", 0, 133, "0xA", "0xC", 0, 4, 0)
      assert(spellGoSeen and spellGoSeen[1] == 133 and spellGoSeen[3] == "0xC" and spellGoSeen[4] == 4,
        "spell-go was not republished on the bus with its targets-hit count")

      -- A stranger's summon stays a stranger: its owner is not in the group,
      -- so it is neither credited to the player nor given a bar of its own.
      TestRegisterGUIDUnit("0xT2", "Infernal", "WARRIOR", false, 500, 500)
      TestSetUnitSummoner("0xT2", "0xSTRANGER")
      fire("SPELL_GO_OTHER", 0, 22703, "0xT2", "0x0000000000000000", 0, 1, 0)
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT2", 22703, 255, "0,0,0", 0, 2, "2,0,0,0")
      assert(alice.damage == damageBefore,
        "a stranger's summon was credited to the player")
      assert(not current.actors["Infernal"],
        "a stranger's summon became an actor with trackAll off")

      -- A groupmate's summon merges into the groupmate, not the player. Here
      -- the totem is still alive when its damage lands, so no SPELL_GO is
      -- needed: the first damage packet reads the summoner itself.
      TestRegisterGUIDUnit("0xT3", "Shadowfiend", "WARRIOR", true, 50, 50)
      TestSetUnitSummoner("0xT3", "0xB")
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT3", 8092, 70, "0,0,0", 0, 5, "2,0,0,0")
      assert(alice.damage == damageBefore, "a groupmate's summon was credited to the player")
      assert(bob.damageSpells["[Shadowfiend] Mind Blast"] and bob.damageSpells["[Shadowfiend] Mind Blast"].amount == 70,
        "a groupmate's summon was not merged into the groupmate")

      -- A roster rebuild mid-fight (a groupmate resummons a pet, someone
      -- joins) wipes every identity, summons included. A summon still alive
      -- must be adopted again on its next packet rather than trusting a
      -- cached "already checked" answer from the old roster.
      Skada.Data:RebuildRoster()
      assert(not Skada.Data:GetIdentityByGUID("0xT3"), "the rebuild kept the summon identity")
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT3", 8092, 30, "0,0,0", 0, 5, "2,0,0,0")
      bob = current.actors["Bob"]
      assert(bob.damageSpells["[Shadowfiend] Mind Blast"].amount == 100,
        "a live summon was not re-adopted after a roster rebuild: " .. tostring(bob.damageSpells["[Shadowfiend] Mind Blast"].amount))

      -- The summoner field and UnitGUID come from different client
      -- extensions. When the owner GUID misses the roster index, the owner
      -- is named and looked up instead of being written off.
      TestRegisterGUIDUnit("0xa", "Alice", "MAGE", true, 1000, 1000)
      TestRegisterGUIDUnit("0xT4", "Magma Totem", "WARRIOR", true, 5, 5)
      TestSetUnitSummoner("0xT4", "0xa")
      fire("SPELL_DAMAGE_EVENT_OTHER", "0xC", "0xT4", 133, 40, "0,0,0", 0, 2, "2,0,0,0")
      alice = current.actors["Alice"]
      assert(alice.damageSpells["[Magma Totem] Fireball"] and alice.damageSpells["[Magma Totem] Fireball"].amount == 40,
        "an owner GUID in a different spelling was not resolved by name")
      TestUnregisterGUIDUnit("0xa")
      damageBefore = alice.damage

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
