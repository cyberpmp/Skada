"""Suite: threat - TWTv4 protocol, rows, TPS, estimate fallback, spell metadata."""

from harness import Context


def run(ctx: Context):
    ctx.run(r'''
      local primary = Skada.UI:GetPrimary()
      Skada.Threat:Update(GetTime())
      assert(TestAddonPrefix == nil)
      primary.db.segment = "total"
      assert(Skada.Modes:Set("threat", primary))
      assert(primary.db.segment == "current")
      assert(Skada.UI:NeedsContinuousRefresh())

      local savedUnitAffectingCombat = UnitAffectingCombat
      UnitAffectingCombat = function(unit) return unit == "player" end
      Skada.Threat:Update(GetTime())
      assert(TestAddonPrefix == "TWT_UDTSv4")
      assert(TestAddonMessage == "limit=" .. primary.db.rows)
      assert(TestAddonChannel == "PARTY")

      Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "SERVER",
        "TWTv4=Alice:0:1234:67:0;Bob:1:1842:100:1")
      primary:Refresh()
      assert(primary.title.textValue == "Threat: Boar")
      assert(primary.displayCount == 2)
      assert(primary.display[1].label == "Bob" and primary.display[1].value == 1842)
      assert(primary.display[1].text == "1842 (0 TPS, 100%)")
      assert(primary.display[1].threatRow.tank and primary.display[1].threatRow.melee)
      assert(primary.display[2].label == "Alice" and primary.display[2].value == 1234)
      assert(Skada.Data.current.threat == nil and Skada.Data.total.threat == nil)
      local liveRows = Skada.Threat.rows
      Skada.Threat.rows = {
        { name = "Zero", threat = 0, tps = 0, percent = 0, class = "OTHER" },
      }
      primary:Refresh()
      local zeroMaximum = primary.paintMaximum
      Skada.Threat.rows = liveRows
      primary:Refresh()
      assert(zeroMaximum == 1, "an all-zero live meter retained a zero paint maximum")
      local savedShowClassIcons = Skada.db.profile.showClassIcons
      Skada.db.profile.showClassIcons = true
      primary:Refresh()
      assert(primary.rows[1].lastIcon == "class:PRIEST")
      assert(primary.rows[1].icon.texture == Skada.UIStyle.CLASS_ICONS)
      Skada.db.profile.showClassIcons = savedShowClassIcons
      primary:Refresh()
      UnitAffectingCombat = savedUnitAffectingCombat

      local savedRows = primary.db.rows
      primary.db.rows = 30
      Skada.Threat.nextQuery = 0
      Skada.Threat:Update(GetTime())
      assert(TestAddonMessage == "limit=10")
      primary.db.rows = savedRows

      local savedPartyCount = GetNumPartyMembers
      GetNumPartyMembers = function() return 0 end
      TestAddonPrefix, TestAddonMessage, TestAddonChannel = nil, nil, nil
      Skada.Threat.nextQuery = 0
      Skada.Threat:Update(GetTime())
      assert(TestAddonPrefix == nil, "ungrouped threat update sent a party/raid query")
      assert(Skada.Threat:GetTitle() == "Threat: Boar")
      GetNumPartyMembers = savedPartyCount

      TestSetTime(101)
      Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "SERVER", "TWTv4=Alice:0:1834:99:0")
      assert(table.getn(Skada.Threat.rows) == 2)
      assert(Skada.Threat.rowsByName.Alice.tps == 600)
      primary:Refresh()
      assert(primary.display[2].text == "1834 (600 TPS, 99%)")

      local savedAddDoubleLine = GameTooltip.AddDoubleLine
      GameTooltip.captured = {}
      GameTooltip.AddDoubleLine = function(self, label, value)
        self.captured[label] = value
      end
      primary:ShowEntryTooltip({ entry = primary.display[2] })
      assert(GameTooltip.captured.TPS == "600")
      GameTooltip.AddDoubleLine = savedAddDoubleLine

      TestSetTime(103)
      Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "SERVER", "TWTv4=Alice:0:2434:100:0")
      assert(table.getn(Skada.Threat.rows) == 1)
      TestSetTime(100)

      TestSetTarget("Boar", "0xD")
      Skada.Threat:TargetChanged()
      assert(table.getn(Skada.Threat.rows) == 0)
      assert(TestAddonPrefix == "TWT_UDTSv4")
      Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "SERVER",
        "TWTv4=Alice:1:2222:100:0")
      assert(table.getn(Skada.Threat.rows) == 1 and Skada.Threat.rows[1].threat == 2222)

      Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "SERVER",
        "TWTv4=Bob:1:3000:100:1;Charlie:0:2000:67:0;Alice:0:1000:33:0")
      primary.db.rows = 2
      primary:Refresh()
      assert(primary.displayCount == 2)
      assert(primary.display[1].label == "Bob")
      assert(primary.display[2].label == "Alice" and primary.display[2].rank == 3)
      assert(primary.rows[2].left.textValue == "3. Alice")
      assert(primary.rows[2].lastR == 1 and primary.rows[2].lastG == 0.2 and primary.rows[2].lastB == 0.2)
      primary.db.rows = 1
      primary:Refresh()
      assert(primary.display[1].label == "Alice" and primary.paintMaximum == 3000)
      primary.db.rows = savedRows

      local estimator = Skada.ThreatEstimate
      local aliceIdentity = Skada.Data:GetIdentityByName("Alice")
      local bobIdentity = Skada.Data:GetIdentityByName("Bob")
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      Skada.Threat.lastResponse = nil
      Skada.Threat.lastServerResponse = nil
      Skada.Threat.usingEstimate = false

      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 100)
      TestSetTarget("Wolf", "0xE")
      Skada.Threat:TargetChanged()
      estimator:RecordDamage("Alice", aliceIdentity, "Wolf", 200, "Fireball", 133, 100)
      estimator:RecordHealing("Bob", bobIdentity, 200, 100)
      assert(estimator.enemyCount == 2, "fallback threat enemy count drifted while adding targets")

      local pooledRows = {}
      local _, pooledCount = estimator:Build("Wolf", "0xE", pooledRows)
      assert(pooledCount == 2)
      local firstPooledRow, secondPooledRow = pooledRows[1], pooledRows[2]
      estimator:Build("Wolf", "0xE", pooledRows)
      assert(pooledRows[1] == firstPooledRow and pooledRows[2] == secondPooledRow,
        "fallback threat projection reallocated stable actor rows")

      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      TestSetTime(103)
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.usingEstimate)
      assert(Skada.Threat.rowsByName.Alice.threat == 100)
      assert(Skada.Threat.rowsByName.Bob.threat == 50)
      assert(Skada.Threat.rowsByName.Alice.estimated)
      assert(Skada.Threat:GetTitle() == "Threat: Boar (estimated)")

      TestSetTarget("Wolf", "0xE")
      Skada.Threat:TargetChanged()
      TestSetTime(106)
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.rowsByName.Alice.threat == 200)
      assert(Skada.Threat.rowsByName.Bob.threat == 50)

      local spellRecordReads = {}
      GetSpellRecField = function(spellID, field)
        spellRecordReads[field] = (spellRecordReads[field] or 0) + 1
        if spellID == 7386 and field == "effect" then return { 63, 0, 0 } end
        if spellID == 7386 and field == "effectBasePoints" then return { 99, -1, -1 } end
        if spellID == 99999 and field == "attributesEx" then return 1024 end
      end
      estimator:ClearSpellMetadataCache()
      estimator:RecordSpellGo(7386, "0xA", "0xE", 1, 106)
      estimator:RecordDamage("Alice", aliceIdentity, "Wolf", 500, "No Threat Test", 99999, 106)
      estimator:RecordDamage("Alice", aliceIdentity, "Wolf", 500, "No Threat Test", 99999, 106)
      estimator:GetExplicitSpellThreat(7386)
      assert(spellRecordReads.effect == 1 and spellRecordReads.effectBasePoints == 1)
      assert(spellRecordReads.attributesEx == 1, "spell threat metadata was not cached")
      TestSetTime(107)
      Skada.Threat:ApplyEstimate(GetTime(), "Wolf", "0xE")
      assert(Skada.Threat.rowsByName.Alice.threat == 300)
      GetSpellRecField = nil

      estimator:RemoveEnemy("0xE")
      assert(not estimator.threatByEnemyKey["0xE"] and not estimator.enemyByKey["0xE"])
      assert(not estimator.enemyKeyByName.Wolf)
      assert(estimator.enemyCount == 1, "fallback threat enemy count drifted while removing a target")
      local removedRows, removedCount = estimator:Build("Wolf", "0xE", {})
      assert(removedCount == 0 and table.getn(removedRows) == 0)

      estimator:Reset()
      assert(estimator.enemyCount == 0)
      local savedUnitExists = UnitExists
      local unitLookupCount = 0
      UnitExists = function(unit)
        unitLookupCount = unitLookupCount + 1
        return savedUnitExists(unit)
      end
      estimator:RecordDamage("Alice", aliceIdentity, "Unseen Enemy", 10, "Fireball", 133, 107)
      local firstLookupCount = unitLookupCount
      estimator:RecordDamage("Alice", aliceIdentity, "Unseen Enemy", 10, "Fireball", 133, 107)
      assert(firstLookupCount > 0 and unitLookupCount == firstLookupCount,
        "cached enemy name triggered another unit scan")
      estimator:RemoveEnemy("Unseen Enemy")
      assert(not estimator.enemyKeyByName["Unseen Enemy"])
      UnitExists = savedUnitExists

      TestSetTarget("Twin Enemy", "0xOLD")
      estimator:ObserveCurrentEnemy(107)
      estimator:RecordDamage("Alice", aliceIdentity, "Twin Enemy", 10, "Fireball", 133, 107)
      TestSetTarget("Twin Enemy", "0xNEW")
      estimator:ObserveCurrentEnemy(107)
      -- The first twin keeps its table; only the name mapping moves.
      assert(estimator.threatByEnemyKey["0xOLD"] and estimator.enemyByKey["0xOLD"],
        "retargeting a same-named mob dropped the first mob's threat table")
      assert(estimator.enemyKeyByName["Twin Enemy"] == "0xNEW")
      assert(estimator.enemyCount == 2,
        "fallback threat enemy count drifted while promoting a name to a GUID")
      TestSetTarget("Wolf", "0xE")

      local wolfIdentity = Skada.Data:GetIdentityByName("Wolf")
      local savedMergePets = Skada.db.profile.mergePets
      Skada.db.profile.mergePets = false
      TestSetPartyMembers(0)
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      Skada.Threat.lastResponse = nil
      Skada.Threat.lastServerResponse = nil
      Skada.Threat.usingEstimate = false

      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      TestSetTime(110)
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 110)
      -- Solo players never get a server reply, so the estimate must paint
      -- on the very first tick after a target switch instead of after a
      -- wait for data that cannot arrive.
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.usingEstimate and Skada.Threat.rowsByName.Alice,
        "solo threat estimate was held back after a target switch")
      estimator:RecordDamage("Bob", bobIdentity, "Boar", 100, "Fireball", 133, 110)
      estimator:RecordDamage("Wolf", wolfIdentity, "Boar", 50, "Bite", 1, 110)
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.usingEstimate)
      assert(Skada.Threat.rowsByName.Alice and Skada.Threat.rowsByName.Alice.threat == 100,
        "ungrouped threat window dropped the player's own estimate")
      assert(Skada.Threat.rowsByName.Wolf and Skada.Threat.rowsByName.Wolf.threat == 50,
        "ungrouped threat window dropped the player's pet estimate")
      assert(Skada.Threat.rowsByName.Bob == nil,
        "ungrouped threat window showed a groupmate's estimate")
      assert(Skada.Threat:GetTitle() == "Threat: Boar (estimated)")

      TestSetPartyMembers(1)
      Skada.Data:RebuildRoster()
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      TestSetTime(112)
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 112)
      estimator:RecordDamage("Bob", bobIdentity, "Boar", 100, "Fireball", 133, 112)
      local groupedRows, groupedCount = estimator:Build("Boar", "0xC", {})
      assert(groupedCount == 2)

      TestSetPartyMembers(0)
      Skada.Data:RebuildRoster()
      Skada.Threat:GroupChanged()
      local soloRows, soloCount = estimator:Build("Boar", "0xC", {})
      assert(soloCount == 1 and soloRows[1].name == "Alice",
        "leaving a group mid-combat kept a former groupmate's estimated threat")

      -- Two mobs sharing a name: damage lands on the one currently targeted,
      -- and switching between them keeps both threat tables.
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      TestSetTime(113)
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 300, "Fireball", 133, 113)
      TestSetTarget("Boar", "0xD")
      Skada.Threat:TargetChanged()
      -- PLAYER_TARGET_CHANGED refreshes the probe cache; the direct test
      -- flow raises no events, so the refresh is called where the event
      -- would fire.
      estimator:ProbeTargetToken()
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 113)
      local secondRows, secondCount = estimator:Build("Boar", "0xD", {})
      assert(secondCount == 1 and secondRows[1].threat == 100,
        "damage on the second same-named mob did not land on the targeted mob")
      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      estimator:ProbeTargetToken()
      TestSetTime(114)
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.rowsByName.Alice and Skada.Threat.rowsByName.Alice.threat == 300,
        "targeting a same-named mob erased the first mob's threat table")
      -- A name-only death line ("Boar dies.") must take the other Boar, not
      -- the live target being fought, so its threat carries on.
      estimator:RemoveEnemy("Boar")
      assert(estimator.threatByEnemyKey["0xC"] and not estimator.threatByEnemyKey["0xD"],
        "a same-named death removed the live target instead of the fallen mob")
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 114)
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.rowsByName.Alice.threat == 400,
        "threat did not carry on after the other same-named mob died")
      -- When the target itself is the one that died, only its table goes:
      -- the other same-named mob keeps the threat built on it.
      TestSetTarget("Boar", "0xD")
      Skada.Threat:TargetChanged()
      estimator:ProbeTargetToken()
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 114)
      assert(estimator.threatByEnemyKey["0xD"] and estimator.threatByEnemyKey["0xC"])
      local savedUnitIsDead = UnitIsDead
      UnitIsDead = function(unit) return unit == "target" end
      estimator:RemoveEnemy("Boar")
      UnitIsDead = savedUnitIsDead
      assert(not estimator.threatByEnemyKey["0xD"],
        "a dead target's threat table survived its death line")
      assert(estimator.threatByEnemyKey["0xC"] and estimator.threatByEnemyKey["0xC"].Alice.threat == 400,
        "killing one same-named mob wiped the threat built on the other")
      TestSetTarget("Boar", "0xC")
      Skada.Threat:TargetChanged()
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.rowsByName.Alice and Skada.Threat.rowsByName.Alice.threat == 400,
        "the surviving same-named mob did not show its earlier threat")

      -- The live-target rule is the player's own heuristic: a groupmate's
      -- damage line names whatever mob it names and must not repoint the
      -- name at the mob the player happens to target.
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      TestSetTarget("Boar", "0xC")
      estimator:ProbeTargetToken()
      TestSetTime(115)
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 115)
      assert(estimator.enemyKeyByName["Boar"] == "0xC")
      TestSetTarget("Boar", "0xD")
      estimator:ProbeTargetToken()
      estimator:RecordDamage("Bob", bobIdentity, "Boar", 100, "Fireball", 133, 115)
      assert(estimator.enemyKeyByName["Boar"] == "0xC",
        "a groupmate's damage line repointed the name at the player's target")
      assert(estimator.threatByEnemyKey["0xD"] == nil,
        "a groupmate's damage line credited the player's targeted mob")
      assert(estimator.threatByEnemyKey["0xC"] and estimator.threatByEnemyKey["0xC"].Bob.threat == 100,
        "a groupmate's damage line did not land on the mob the name mapped to")

      -- An untracked corpse parked on the target stops the removal where it
      -- stands: the survivor sweep must not take a live twin's table.
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      TestSetTarget("Boar", "0xC")
      estimator:ProbeTargetToken()
      TestSetTime(116)
      estimator:RecordDamage("Alice", aliceIdentity, "Boar", 100, "Fireball", 133, 116)
      assert(estimator.threatByEnemyKey["0xC"])
      local savedUnitIsDeadForCorpse = UnitIsDead
      UnitIsDead = function(unit) return unit == "target" end
      TestSetTarget("Boar", "0xDEAD")
      estimator:ProbeTargetToken()
      estimator:RemoveEnemy("Boar")
      UnitIsDead = savedUnitIsDeadForCorpse
      assert(estimator.threatByEnemyKey["0xC"],
        "an untracked corpse on the target swept a live twin's table away")
      assert(estimator.enemyKeyByName["Boar"] == "0xC",
        "an untracked corpse on the target dropped the live twin's name mapping")

      -- Idle expiry drops the table and the name mapping with the record, so
      -- a stale mapping cannot re-register the mob on a later hit.
      estimator:Reset()
      Skada.Threat:ClearRows(true)
      TestSetTarget("Boar", "0xC")
      estimator:ProbeTargetToken()
      TestSetTime(200)
      estimator:RecordDamage("Alice", aliceIdentity, "Idle Mob", 50, "Fireball", 133, 200)
      assert(estimator.enemyKeyByName["Idle Mob"] ~= nil)
      TestSetTime(240)
      estimator:RecordHealing("Bob", bobIdentity, 10, 240)
      assert(estimator.threatByEnemyKey[estimator.enemyKeyByName["Idle Mob"]] == nil,
        "an expired mob's threat table outlived its record")
      assert(estimator.enemyKeyByName["Idle Mob"] == nil,
        "an expired mob's name mapping outlived its record")
      TestSetTime(241)
      estimator:RecordDamage("Alice", aliceIdentity, "Idle Mob", 25, "Fireball", 133, 241)
      local idleKey = estimator.enemyKeyByName["Idle Mob"]
      assert(idleKey ~= nil)
      local idleThreat = estimator.threatByEnemyKey[idleKey]
      assert(idleThreat and idleThreat.Alice.threat == 25,
        "an expired mob's stale mapping re-registered it on the next hit")

      TestSetPartyMembers(1)
      Skada.Data:RebuildRoster()
      Skada.db.profile.mergePets = savedMergePets
      TestSetTarget("Wolf", "0xE")
      Skada.Threat:TargetChanged()

      Skada.Threat.requestTarget = "0xE"
      Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "SERVER", "TWTv4=Alice:1:5000:100:1")
      assert(not Skada.Threat.usingEstimate)
      assert(Skada.Threat.rowsByName.Alice.threat == 5000)
      assert(not Skada.Threat.rowsByName.Alice.estimated)

      -- A groupmate cannot pose as the threat server: the client stamps
      -- the real sender on player addon messages. Neither can a guildmate
      -- outside the group, nor a packet carrying escapes or impossible values.
      local function sendForged(message, channel, sender)
        Skada.Threat.requestTarget = "0xE"
        Skada.Threat:OnAddonMessage("CHAT_MSG_ADDON", "TWT", message, channel, sender)
      end
      Skada.Threat.rejectionReported = nil
      local rejectedBefore = Skada.Threat.rejectedPackets or 0
      sendForged("TWTv4=Bob:1:99999:100:1", "PARTY", "Bob")
      assert(not Skada.Threat.rowsByName.Bob and Skada.Threat.rowsByName.Alice.threat == 5000,
        "a groupmate's forged threat packet was accepted")
      -- A pet named after the forger must not hide them from the roster check.
      local forgerIdentity = Skada.Data:GetIdentityByName("Bob")
      local savedOwner = forgerIdentity.owner
      forgerIdentity.owner = "Bob"
      sendForged("TWTv4=Bob:1:99999:100:1", "RAID", "Bob")
      forgerIdentity.owner = savedOwner
      sendForged("TWTv4=Bob:1:99999:100:1", "GUILD", "Mallory")
      sendForged("TWTv4=Bob:1:99999:100:1", "BATTLEGROUND", "Mallory")
      sendForged("TWTv4=|Hitem:1|h[x]|h:1:99999:100:1", "PARTY", "")
      sendForged("TWTv4=Bob:1:1e999:100:1", "PARTY", "")
      sendForged("TWTv4=" .. string.rep("Bob:0:1:1:0;", 41), "PARTY", "")
      assert(not Skada.Threat.rowsByName.Bob and Skada.Threat.rowsByName.Alice.threat == 5000,
        "a forged threat packet replaced the live table")
      assert(Skada.Threat.rejectedPackets == rejectedBefore + 7)
      -- The player's own name (and a blank sender) is how a server reply arrives.
      sendForged("TWTv4=Alice:1:6000:100:1", "PARTY", "Alice")
      assert(Skada.Threat.rowsByName.Alice.threat == 6000, "a reply addressed from the player was dropped")

      -- No reply ever: after the unanswered limit, queries slow to the
      -- backoff interval until a reply arrives or the group changes.
      Skada.Threat.receivedPackets = 0
      Skada.Threat.unansweredQueries = Skada.Threat.unansweredLimit
      local savedCombatCheck = UnitAffectingCombat
      UnitAffectingCombat = function(unit) return unit == "player" end
      Skada.Threat.nextQuery = 0
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.nextQuery == GetTime() + Skada.Threat.backoffInterval,
        "an unanswered threat provider kept querying at full rate")
      Skada.Threat.receivedPackets = 1
      Skada.Threat.nextQuery = 0
      Skada.Threat:Update(GetTime())
      assert(Skada.Threat.nextQuery < GetTime() + Skada.Threat.backoffInterval,
        "a group that has heard the server was put on backoff")
      UnitAffectingCombat = savedCombatCheck
      Skada.Threat:GroupChanged()
      assert(Skada.Threat.unansweredQueries < Skada.Threat.unansweredLimit,
        "a new group inherited the old group's threat backoff")

      TestSetTime(100)
      TestSetTarget("Boar", "0xD")

      primary.db.segment = "total"
      assert(Skada.Modes:Set("threat", primary))
      assert(primary.db.segment == "current")
      assert(Skada.Modes:Set("damage", primary))
    ''')
