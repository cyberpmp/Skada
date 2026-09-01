"""Suite: boss_detection - boss classification, BigWigs interop, group-target poll."""

from harness import Context


def run(ctx: Context):
    ctx.run(r'''
      local historyCount = table.getn(Skada.Data.history)
      local profile = Skada.db.profile

      profile.onlyBossFights = true
      Skada.Data.active = true
      Skada.Data.current.hasData = true
      Skada.Data:EndSegment(430)
      assert(table.getn(Skada.Data.history) == historyCount,
        "non-boss fight must be dropped when boss-only is on")

      Skada.Data.active = true
      Skada.Data.current.hasData = true
      Skada.Data.current.gotboss = true
      Skada.Data:EndSegment(440)
      assert(table.getn(Skada.Data.history) == historyCount + 1,
        "a boss-flagged fight must still be archived")
      assert(Skada.Data.history[1].gotboss == true)

      TestSetTime(450)
      Skada.Data:OnCombatEnter(450)
      TestSetTime(451)
      Skada.Data:RecordDamage("Alice", "Flamewaker Healer", 10, "Fireball", 133, nil, false, 451)
      local realUnitExists = UnitExists
      local realUnitName = UnitName
      local realUnitGUID = UnitGUID
      local realUnitIsPlayer = UnitIsPlayer
      local realGetCreatureID = C_CreatureInfo.GetCreatureID
      local realGetCreatureInfoByID = C_CreatureInfo.GetCreatureInfoByID
      local realGroupTokens = Skada.Data.groupTokens
      local realBigWigs = BigWigs
      local targetUnit, targetName, targetRank, targetIsPlayer = "target", "Flamewaker Healer", 1, false
      local inspectedUnits = {}
      TestSetCombat(true)
      UnitExists = function(unit)
        inspectedUnits[unit] = (inspectedUnits[unit] or 0) + 1
        return unit == targetUnit
      end
      UnitName = function(unit) if unit == targetUnit then return targetName end return realUnitName(unit) end
      UnitGUID = function(unit) if unit == targetUnit then return "0xBOSS" end return realUnitGUID(unit) end
      UnitIsPlayer = function(unit) if unit == targetUnit then return targetIsPlayer end return realUnitIsPlayer(unit) end
      C_CreatureInfo.GetCreatureID = function(guid) if guid == "0xBOSS" then return 11502 end end
      C_CreatureInfo.GetCreatureInfoByID = function() return { rank = targetRank } end
      UnitClassification = function() return targetRank == 3 and "worldboss" or "elite" end
      Skada.Data.groupTokens = { "player", "pet", "party1", "partypet1" }
      Skada.Data:Update(452)
      assert(not Skada.Data.current.gotboss, "elite raid add was treated as a boss")
      assert(not inspectedUnits.pettarget and not inspectedUnits.partypet1target,
        "boss target scan inspected pet targets")
      local inspectedCount = 0
      for _, count in pairs(inspectedUnits) do inspectedCount = inspectedCount + count end
      Skada.Data:Update(452.2)
      local throttledCount = 0
      for _, count in pairs(inspectedUnits) do throttledCount = throttledCount + count end
      assert(throttledCount == inspectedCount, "boss target scan was not throttled")

      targetName, targetRank, targetIsPlayer = "Enemy Player", 3, true
      Skada.Data:Update(453)
      assert(not Skada.Data.current.gotboss, "player target was treated as a boss")

      local loadedModules = {
        {
          bossSync = "Ancient Core Hound",
          translatedName = "Ancient Core Hound",
          engaged = true,
          enabletrigger = "Ancient Core Hound",
          toggleoptions = { "bars" },
        },
      }
      BigWigs = {
        IterateModules = function()
          local moduleIndex = 0
          return function()
            moduleIndex = moduleIndex + 1
            local module = loadedModules[moduleIndex]
            if module then return module.translatedName, module end
          end
        end,
      }
      targetUnit, targetName, targetRank, targetIsPlayer = "target", "Flamewaker Healer", 1, false
      Skada.Data:Update(454)
      assert(not Skada.Data.current.gotboss, "engaged BigWigs trash was treated as a boss")

      loadedModules[2] = {
        bossSync = "Majordomo Executus",
        translatedName = "Majordomo Executus",
        engaged = true,
        enabletrigger = { "Majordomo Executus", "Flamewaker Healer" },
        wipemobs = { "Flamewaker Healer", "Flamewaker Elite" },
        toggleoptions = { "adds", "bosskill" },
      }
      Skada.BossDetection:ClearBigWigsCache()
      Skada.Data:Update(455)
      assert(Skada.Data.current.gotboss, "engaged BigWigs boss module was not recognized")
      assert(Skada.Data.current.name == "Majordomo Executus",
        "BigWigs wipe mob replaced the canonical encounter name")
      assert(not Skada.Data.current.bossID, "a wipe mob ID was stored as the boss ID")

      Skada.Data.current.gotboss = nil
      Skada.Data.current.name = "Current"
      Skada.Data.nextBossTargetScan = nil
      loadedModules[2].engaged = false
      targetName, targetRank = "Majordomo Executus", 1
      Skada.Data:Update(456)
      assert(Skada.Data.current.gotboss and Skada.Data.current.name == "Majordomo Executus",
        "BigWigs primary trigger did not identify a custom-rank boss")

      Skada.Data.current.gotboss = nil
      Skada.Data.current.bossID = nil
      Skada.Data.current.name = "Current"
      Skada.Data.nextBossTargetScan = nil
      BigWigs = realBigWigs
      targetUnit, targetName, targetRank, targetIsPlayer = "party1target", "Ragnaros", 3, false
      Skada.Data:Update(457)
      assert(Skada.Data.current.gotboss, "group-target boss poll did not flag the fight")
      assert(Skada.Data.current.bossID == 11502)
      assert(Skada.Data.current.name == "Ragnaros")
      UnitExists = realUnitExists
      UnitName = realUnitName
      UnitGUID = realUnitGUID
      UnitIsPlayer = realUnitIsPlayer
      C_CreatureInfo.GetCreatureID = realGetCreatureID
      C_CreatureInfo.GetCreatureInfoByID = realGetCreatureInfoByID
      UnitClassification = nil
      Skada.Data.groupTokens = realGroupTokens
      BigWigs = realBigWigs
      TestSetCombat(false)

      profile.onlyBossFights = false
      Skada.Data.active = true
      Skada.Data.current.hasData = true
      Skada.Data:EndSegment(460)
      assert(table.getn(Skada.Data.history) == historyCount + 2,
        "normal fights must archive again when boss-only is off")
    ''')