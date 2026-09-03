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
      assert(not estimator.threatByEnemyKey["0xOLD"] and not estimator.enemyByKey["0xOLD"])
      assert(estimator.enemyKeyByName["Twin Enemy"] == "0xNEW")
      assert(estimator.enemyCount == 1,
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
      TestSetTime(100)
      TestSetTarget("Boar", "0xD")

      primary.db.segment = "total"
      assert(Skada.Modes:Set("threat", primary))
      assert(primary.db.segment == "current")
      assert(Skada.Modes:Set("damage", primary))
    ''')
