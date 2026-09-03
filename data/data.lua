local Skada = (_G or getfenv(0)).Skada

local Data = {}
Skada.Data = Data

local DataIdentity = Skada.DataIdentity
local DataAggregator = Skada.DataAggregator
local DataSegments = Skada.DataSegments
local DataNavigation = Skada.DataNavigation

local Common = Skada.Common
local trim = Common.Trim

local type = type
local tonumber = tonumber
local max = math.max
local min = math.min

local recordDamageSet = DataAggregator.RecordDamageSet
local recordHealingSet = DataAggregator.RecordHealingSet
local recordPowerSet = DataAggregator.RecordPowerSet
local recordCountSet = DataAggregator.RecordCountSet
local recordDeathSet = DataAggregator.RecordDeathSet
local recordDurationSet = DataAggregator.RecordDurationSet

Data.AddObservedUnit = DataIdentity.AddObservedUnit
Data.AddGroupUnit = DataIdentity.AddGroupUnit
Data.RebuildRoster = DataIdentity.RebuildRoster
Data.ObserveToken = DataIdentity.ObserveToken
Data.FindUnitByName = DataIdentity.FindUnitByName
Data.GetIdentityByGUID = DataIdentity.GetIdentityByGUID
Data.GetIdentityByName = DataIdentity.GetIdentityByName
Data.ResolveSource = DataIdentity.ResolveSource
Data.ResolveTarget = DataIdentity.ResolveTarget

Data.StartSegment = DataSegments.StartSegment
Data.EnsureSegment = DataSegments.EnsureSegment
Data.GetSetDuration = DataSegments.GetSetDuration
Data.EachLiveSet = DataSegments.EachLiveSet
Data.IsGroupInCombat = DataSegments.IsGroupInCombat
Data.OnCombatEnter = DataSegments.OnCombatEnter
Data.OnCombatLeave = DataSegments.OnCombatLeave
Data.EndSegment = DataSegments.EndSegment
Data.Update = DataSegments.Update
Data.Reset = DataSegments.Reset
Data.TrimHistory = DataSegments.TrimHistory

Data.GetSegmentLabel = DataNavigation.GetSegmentLabel
Data.GetSegmentChoices = DataNavigation.GetSegmentChoices
Data.CycleSegment = DataNavigation.CycleSegment

function Data:Initialize()
  local now = GetTime()
  self.identitiesByName = {}
  self.identitiesByGUID = {}
  self.unitsByName = {}
  self.groupTokens = {}
  self.history = {}
  self.total = DataAggregator:NewSet("Overall", now, true)
  self.current = DataAggregator:NewSet("Current", now, false)
  self.active = false
  self.clientInCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false
  self.combatStateKnown = self.clientInCombat
  self.noCombatSince = nil
  self.playerName = UnitName("player") or "Player"
  self.healingMissByName = {}
  self.healingMissPrune = 0
  self:RebuildRoster()
end

function Data:RecordDamage(sourceName, targetName, amount, spellName, spellID, school, critical, now, mitigationType, mitigationAmount)
  amount = tonumber(amount) or 0
  local hasMitigation = mitigationType and mitigationAmount and mitigationAmount > 0
  if amount <= 0 and not hasMitigation then return end
  now = now or GetTime()

  local actorName, sourceIdentity, petName = self:ResolveSource(sourceName)
  local targetActorName, targetIdentity, rawTargetName = self:ResolveTarget(targetName)
  if not actorName and not targetActorName then return end

  local segmentName
  if not targetActorName then segmentName = rawTargetName end
  if not self:EnsureSegment(now, segmentName, true) then return end
  local selfDamage = actorName and targetActorName and actorName == targetActorName
  if petName then spellName = "[" .. petName .. "] " .. (spellName or "Attack") end

  recordDamageSet(DataAggregator, self.current, actorName, sourceIdentity, targetActorName, targetIdentity, amount, spellName, spellID, critical, selfDamage, now, rawTargetName, mitigationType, mitigationAmount)
  recordDamageSet(DataAggregator, self.total, actorName, sourceIdentity, targetActorName, targetIdentity, amount, spellName, spellID, critical, selfDamage, now, rawTargetName, mitigationType, mitigationAmount)
  if actorName and not selfDamage and not targetActorName and rawTargetName then
    Skada:Publish("damageRecorded", actorName, sourceIdentity, rawTargetName, amount, spellName, spellID, now)
  end
  if Skada.Tracking then Skada.Tracking:NoteDamage(sourceName, targetName, spellName, now) end
  Skada:MarkDirty()
  return true
end

function Data:RecordHealing(sourceName, targetName, amount, spellName, spellID, critical, now)
  amount = tonumber(amount)
  if not amount or amount <= 0 then return end
  now = now or GetTime()

  local actorName, identity, petName = self:ResolveSource(sourceName)
  if not actorName then return end

  if not self:EnsureSegment(now, nil, false) then return end
  if petName then spellName = "[" .. petName .. "] " .. (spellName or "Heal") end
  local rawTargetName = trim(targetName)
  local effective, overhealing, verified = self:EstimateHealing(rawTargetName, amount, now)

  recordHealingSet(DataAggregator, self.current, actorName, identity, amount, effective, overhealing, verified, spellName, spellID, critical, now, rawTargetName)
  recordHealingSet(DataAggregator, self.total, actorName, identity, amount, effective, overhealing, verified, spellName, spellID, critical, now, rawTargetName)
  Skada:Publish("healingRecorded", actorName, identity, effective, now)
  Skada:MarkDirty()
  return true
end

function Data:EstimateHealing(targetName, amount, now)
  now = now or GetTime()
  local missedAt = self.healingMissByName[targetName]
  if missedAt and now - missedAt < 0.5 then
    return amount, 0, false
  end

  if now - self.healingMissPrune > 5 then
    self.healingMissPrune = now
    local name, stamp
    for name, stamp in pairs(self.healingMissByName) do
      if now - stamp > 5 then self.healingMissByName[name] = nil end
    end
  end

  local unit = self:FindUnitByName(targetName)
  if unit and UnitHealth and UnitHealthMax then
    local health = tonumber(UnitHealth(unit))
    local maximum = tonumber(UnitHealthMax(unit))
    if health and maximum and maximum > 0 then
      self.healingMissByName[targetName] = nil
      local effective = min(amount, max(0, maximum - health))
      return effective, amount - effective, true
    end
  end

  if not missedAt or now - missedAt >= 0.5 then
    self.healingMissByName[targetName] = now
  end
  return amount, 0, false
end

function Data:RecordPower(gainerName, sourceName, amount, powerType, spellName, spellID, now)
  amount = tonumber(amount)
  if not amount or amount <= 0 then return end
  now = now or GetTime()

  local actorName, identity, petName = self:ResolveSource(gainerName)
  if not actorName then return end
  if not self:EnsureSegment(now, nil, false) then return end
  spellName = spellName or "Power"
  if petName then spellName = "[" .. petName .. "] " .. spellName end

  recordPowerSet(DataAggregator, self.current, actorName, identity, amount, spellName, spellID, powerType, now)
  recordPowerSet(DataAggregator, self.total, actorName, identity, amount, spellName, spellID, powerType, now)
  Skada:MarkDirty()
  return true
end

function Data:RecordMiss(sourceName, targetName, spellName, avoidType, now)
  self:RecordCount("misses", "missSpells", sourceName, targetName, spellName, spellName, nil, 1, now)
  self:RecordCount("avoids", "avoidSpells", targetName, sourceName, avoidType, avoidType, nil, 1, now)
end

function Data:RecordCount(field, detailField, sourceName, targetName, abilityName, detailName, spellID, count, now)
  count = count or 1
  now = now or GetTime()
  local actorName, identity, petName = self:ResolveSource(sourceName)
  if not actorName then return end
  if not self:EnsureSegment(now, targetName, false) then return end
  if petName then abilityName = "[" .. petName .. "] " .. (abilityName or field) end

  local resolvedDetail = detailName or abilityName or field
  recordCountSet(DataAggregator, self.current, actorName, identity, field, detailField, resolvedDetail, spellID, count, now)
  recordCountSet(DataAggregator, self.total, actorName, identity, field, detailField, resolvedDetail, spellID, count, now)
  Skada:MarkDirty()
  return true
end

function Data:RecordInterrupt(sourceName, targetName, abilityName, interruptedName, spellID, now)
  return self:RecordCount("interrupts", "interruptSpells", sourceName, targetName, abilityName, interruptedName or abilityName, spellID, 1, now)
end

function Data:RecordDispel(sourceName, targetName, abilityName, auraName, spellID, now)
  return self:RecordCount("dispels", "dispelSpells", sourceName, targetName, abilityName, auraName or abilityName, spellID, 1, now)
end

function Data:RecordCC(sourceName, targetName, spellName, spellID, now)
  return self:RecordCount("cc", "ccSpells", sourceName, targetName, spellName, spellName, spellID, 1, now)
end

function Data:RecordCCBreak(sourceName, targetName, spellName, spellID, now)
  return self:RecordCount("ccBreaks", "ccBreakSpells", sourceName, targetName, spellName, spellName, spellID, 1, now)
end

function Data:RecordDuration(field, detailField, sourceName, spellName, duration)
  if not sourceName or not duration or duration <= 0 then return end

  if not self.active or not self.current then return end
  duration = min(duration, max(0, GetTime() - self.current.startTime))
  if duration <= 0 then return end
  local actorName = self:ResolveSource(sourceName)
  if not actorName then return end
  recordDurationSet(DataAggregator, self.current, actorName, field, detailField, spellName, duration)
  recordDurationSet(DataAggregator, self.total, actorName, field, detailField, spellName, duration)
  Skada:MarkDirty()
end

function Data:RecordCCDuration(sourceName, spellName, spellID, duration)
  self:RecordDuration("ccDuration", "ccSpells", sourceName, spellName, duration)
end

function Data:RecordDebuff(sourceName, targetName, spellName, spellID, now)
  return self:RecordCount("debuffs", "debuffSpells", sourceName, targetName, spellName, spellName, spellID, 1, now)
end

function Data:RecordDebuffDuration(sourceName, spellName, spellID, duration)
  self:RecordDuration("debuffUptime", "debuffSpells", sourceName, spellName, duration)
end

function Data:RecordBuff(sourceName, targetName, spellName, spellID, now)
  return self:RecordCount("buffs", "buffSpells", sourceName, targetName, spellName, spellName, spellID, 1, now)
end

function Data:RecordBuffDuration(sourceName, spellName, spellID, duration)
  self:RecordDuration("buffUptime", "buffSpells", sourceName, spellName, duration)
end

function Data:RecordDeath(targetName, now, killerName, killerSpell)
  now = now or GetTime()
  Skada:Publish("unitDied", trim(targetName))
  local actorName, identity = self:ResolveTarget(targetName)
  if not actorName then return end
  if not self:EnsureSegment(now, nil, false) then return end

  recordDeathSet(DataAggregator, self.current, actorName, identity, now, killerName, killerSpell)
  recordDeathSet(DataAggregator, self.total, actorName, identity, now, killerName, killerSpell)
  Skada:MarkDirty()
end

function Data:GetSelectedSet(selection)
  selection = selection or Skada.db.profile.segment
  if selection == "total" then return self.total end
  if type(selection) == "number" then return self.history[selection] or self.current end
  return self.current
end

function Data:GetPlayerName()
  return self.playerName or UnitName("player") or "Player"
end

Skada:RegisterInitializer(function() Data:Initialize() end, "data")

Skada:RegisterTicker("data", 0.20, function(now) Data:Update(now) end)
