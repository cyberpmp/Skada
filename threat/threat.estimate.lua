local Skada = (_G or getfenv(0)).Skada

local ThreatEstimator = {
  threatByEnemyKey = {},
  enemyByKey = {},
  enemyKeyByName = {},
  damageMultiplierBySpellID = {},
  damageMultiplierBySpellName = {},
  explicitThreatBySpellID = {},
}
Skada.ThreatEstimate = ThreatEstimator

local Common = Skada.Common
local wipeTable = Common.Wipe
local trim = Common.Trim

local floor = math.floor
local max = math.max
local tonumber = tonumber
local type = type
local pairs = pairs
local table_getn = table.getn
local table_sort = table.sort
local string_find = string.find

local ZERO_GUID_LONG = "0x0000000000000000"
local ZERO_GUID_SHORT = "0x000000000"
local NAME_PREFIX = "NAME:"

local SPELL_EFFECT_THREAT = 63
local SPELL_EFFECT_THREAT_ALL = 91
local SPELL_ATTRIBUTE_NO_THREAT = 1024

local SPECIAL_DAMAGE_MULTIPLIER_BY_NAME = {
  ["Mind Blast"] = 2.00,
  ["Searing Pain"] = 2.00,
  ["Shield Slam"] = 1.50,
  ["Revenge"] = 2.00,
  ["Maul"] = 1.75,
  ["Heroic Strike"] = 1.25,
  ["Cleave"] = 1.15,
  ["Thunder Clap"] = 1.75,
  ["Mocking Blow"] = 2.50,
  ["Holy Shield"] = 1.30,
}

local ENEMY_UNIT_CANDIDATES = {
  "target",
  "targettarget",
  "focus",
  "focustarget",
  "mouseover",
}

local function isUsableGUID(guid)
  return guid and guid ~= "" and guid ~= ZERO_GUID_LONG and guid ~= ZERO_GUID_SHORT
end

local function containsBitFlag(value, flag)
  value = tonumber(value) or 0
  local quotient = floor(value / flag)
  return quotient - floor(quotient / 2) * 2 == 1
end

local function readSpellRecordField(spellID, fieldName)
  if not spellID or not GetSpellRecField then return nil end
  local succeeded, value = pcall(GetSpellRecField, spellID, fieldName, 1)
  if succeeded then return value end
end

local function findUnitGUIDByName(enemyName)
  if not enemyName or not UnitExists or not UnitName or not UnitGUID then return nil end

  local candidateIndex, unitToken
  for candidateIndex = 1, table_getn(ENEMY_UNIT_CANDIDATES) do
    unitToken = ENEMY_UNIT_CANDIDATES[candidateIndex]
    if UnitExists(unitToken) and UnitName(unitToken) == enemyName then return UnitGUID(unitToken) end
  end

  local groupTokens = Skada.Data and Skada.Data.groupTokens
  if groupTokens then
    local groupIndex, groupToken
    for groupIndex = 1, table_getn(groupTokens) do
      groupToken = groupTokens[groupIndex]
      if groupToken ~= "player" then
        unitToken = groupToken .. "target"
        if UnitExists(unitToken) and UnitName(unitToken) == enemyName then return UnitGUID(unitToken) end
      end
    end
  end
end

local function mergeActorThreat(destination, source)
  local actorName, sourceActor, destinationActor
  for actorName, sourceActor in pairs(source) do
    destinationActor = destination[actorName]
    if not destinationActor then
      destinationActor = {
        name = sourceActor.name,
        class = sourceActor.class,
        threat = 0,
        melee = false,
      }
      destination[actorName] = destinationActor
    end
    destinationActor.threat = (destinationActor.threat or 0) + (sourceActor.threat or 0)
    destinationActor.melee = destinationActor.melee or sourceActor.melee
    if destinationActor.class == "OTHER" and sourceActor.class then destinationActor.class = sourceActor.class end
  end
end

local function removeEnemyByKey(estimator, enemyKey)
  estimator.threatByEnemyKey[enemyKey] = nil
  estimator.enemyByKey[enemyKey] = nil
  local enemyName, mappedKey
  for enemyName, mappedKey in pairs(estimator.enemyKeyByName) do
    if mappedKey == enemyKey then estimator.enemyKeyByName[enemyName] = nil end
  end
end

function ThreatEstimator:ClearSpellMetadataCache()
  wipeTable(self.damageMultiplierBySpellID)
  wipeTable(self.damageMultiplierBySpellName)
  wipeTable(self.explicitThreatBySpellID)
end

function ThreatEstimator:GetNamedDamageMultiplier(spellName)
  if not spellName then return 1 end
  local cachedMultiplier = self.damageMultiplierBySpellName[spellName]
  if cachedMultiplier ~= nil then return cachedMultiplier end

  local multiplier = SPECIAL_DAMAGE_MULTIPLIER_BY_NAME[spellName]
  if not multiplier then
    local specialSpellName, specialMultiplier
    for specialSpellName, specialMultiplier in pairs(SPECIAL_DAMAGE_MULTIPLIER_BY_NAME) do
      if string_find(spellName, specialSpellName, 1, true) then
        multiplier = specialMultiplier
        break
      end
    end
  end
  multiplier = multiplier or 1
  self.damageMultiplierBySpellName[spellName] = multiplier
  return multiplier
end

function ThreatEstimator:GetDamageMultiplier(spellName, spellID)
  spellID = tonumber(spellID)
  if spellID and self.damageMultiplierBySpellID[spellID] ~= nil then
    return self.damageMultiplierBySpellID[spellID]
  end

  local multiplier = self:GetNamedDamageMultiplier(spellName)
  if spellID then
    local spellAttributes = readSpellRecordField(spellID, "attributesEx")
    if spellAttributes and containsBitFlag(spellAttributes, SPELL_ATTRIBUTE_NO_THREAT) then multiplier = 0 end
    self.damageMultiplierBySpellID[spellID] = multiplier
  end
  return multiplier
end

function ThreatEstimator:PromoteEnemyNameToGUID(enemyName, enemyGUID)
  if not enemyName or not isUsableGUID(enemyGUID) then return end
  local nameKey = NAME_PREFIX .. enemyName
  local previousKey = self.enemyKeyByName[enemyName]
  if previousKey and previousKey ~= nameKey and previousKey ~= enemyGUID then
    removeEnemyByKey(self, previousKey)
  end
  if nameKey ~= enemyGUID and self.threatByEnemyKey[nameKey] then
    local destination = self.threatByEnemyKey[enemyGUID]
    if not destination then
      destination = {}
      self.threatByEnemyKey[enemyGUID] = destination
    end
    mergeActorThreat(destination, self.threatByEnemyKey[nameKey])
    self.threatByEnemyKey[nameKey] = nil
  end

  if nameKey ~= enemyGUID and self.enemyByKey[nameKey] then
    local namedEnemy = self.enemyByKey[nameKey]
    local enemy = self.enemyByKey[enemyGUID]
    if not enemy then
      self.enemyByKey[enemyGUID] = namedEnemy
    elseif (namedEnemy.lastSeen or 0) > (enemy.lastSeen or 0) then
      enemy.lastSeen = namedEnemy.lastSeen
      enemy.name = namedEnemy.name or enemy.name
    end
    self.enemyByKey[nameKey] = nil
  end
  self.enemyKeyByName[enemyName] = enemyGUID
end

function ThreatEstimator:ResolveEnemyKey(enemyName, knownGUID)
  enemyName = trim(enemyName)
  if isUsableGUID(knownGUID) then
    self:PromoteEnemyNameToGUID(enemyName, knownGUID)
    return knownGUID
  end

  local cachedKey = enemyName and self.enemyKeyByName[enemyName]
  if cachedKey then return cachedKey end

  local discoveredGUID = findUnitGUIDByName(enemyName)
  if isUsableGUID(discoveredGUID) then
    self:PromoteEnemyNameToGUID(enemyName, discoveredGUID)
    return discoveredGUID
  end

  if not enemyName then return nil end
  local nameKey = NAME_PREFIX .. enemyName
  self.enemyKeyByName[enemyName] = nameKey
  return nameKey
end

function ThreatEstimator:FindRecordedEnemyKey(enemyName, knownGUID)
  enemyName = trim(enemyName)
  if isUsableGUID(knownGUID) then
    if self.threatByEnemyKey[knownGUID] then return knownGUID end
    local cachedKey = enemyName and self.enemyKeyByName[enemyName]
    if cachedKey and self.threatByEnemyKey[cachedKey] then
      self:PromoteEnemyNameToGUID(enemyName, knownGUID)
      return knownGUID
    end
  end

  local cachedKey = enemyName and self.enemyKeyByName[enemyName]
  if cachedKey and self.threatByEnemyKey[cachedKey] then return cachedKey end
  local nameKey = enemyName and (NAME_PREFIX .. enemyName)
  if nameKey and self.threatByEnemyKey[nameKey] then return nameKey end
end

function ThreatEstimator:RecordEnemyActivity(enemyKey, enemyName, timestamp)
  if not enemyKey then return end
  local enemy = self.enemyByKey[enemyKey]
  if not enemy then
    enemy = {}
    self.enemyByKey[enemyKey] = enemy
  end
  enemy.name = enemyName or enemy.name
  enemy.lastSeen = timestamp or GetTime()
end

function ThreatEstimator:GetOrCreateActorThreat(enemyKey, actorName, identity)
  local enemyThreat = self.threatByEnemyKey[enemyKey]
  if not enemyThreat then
    enemyThreat = {}
    self.threatByEnemyKey[enemyKey] = enemyThreat
  end
  local actorThreat = enemyThreat[actorName]
  if not actorThreat then
    actorThreat = {
      name = actorName,
      class = identity and identity.class or "OTHER",
      threat = 0,
      melee = false,
    }
    enemyThreat[actorName] = actorThreat
  end
  return actorThreat
end

function ThreatEstimator:RecordDamage(actorName, identity, targetName, amount, spellName, spellID, timestamp)
  amount = tonumber(amount) or 0
  if not actorName or not targetName or amount <= 0 then return end
  local enemyKey = self:ResolveEnemyKey(targetName)
  if not enemyKey then return end
  self:RecordEnemyActivity(enemyKey, targetName, timestamp)
  local actorThreat = self:GetOrCreateActorThreat(enemyKey, actorName, identity)
  actorThreat.threat = actorThreat.threat + amount * self:GetDamageMultiplier(spellName, spellID)
  if spellName and (spellName == "Auto Attack" or string_find(spellName, "Auto Attack", 1, true)) then
    actorThreat.melee = true
  end
end

function ThreatEstimator:ObserveCurrentEnemy(timestamp)
  if not UnitExists or not UnitExists("target") or not UnitName then return end
  if UnitIsDead and UnitIsDead("target") then return end
  if UnitIsPlayer and UnitIsPlayer("target") then return end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return end
  local enemyName = UnitName("target")
  local enemyKey = self:ResolveEnemyKey(enemyName, UnitGUID and UnitGUID("target") or nil)
  self:RecordEnemyActivity(enemyKey, enemyName, timestamp)
end

function ThreatEstimator:RecordHealing(actorName, identity, amount, timestamp)
  amount = tonumber(amount) or 0
  if not actorName or amount <= 0 then return end
  self:ObserveCurrentEnemy(timestamp)

  local enemyCount = 0
  local enemyKey
  for enemyKey in pairs(self.enemyByKey) do enemyCount = enemyCount + 1 end
  if enemyCount == 0 then return end

  local threatPerEnemy = amount * 0.5 / enemyCount
  for enemyKey in pairs(self.enemyByKey) do
    local actorThreat = self:GetOrCreateActorThreat(enemyKey, actorName, identity)
    actorThreat.threat = actorThreat.threat + threatPerEnemy
  end
end

function ThreatEstimator:GetActorByGUID(actorGUID)
  local identity = Skada.Data and Skada.Data:GetIdentityByGUID(actorGUID)
  if not identity then return nil end
  if identity.owner then
    return identity.owner, Skada.Data:GetIdentityByName(identity.owner) or identity
  end
  return identity.name, identity
end

function ThreatEstimator:AddExplicitThreat(enemyKey, enemyName, actorName, identity, amount, timestamp)
  amount = tonumber(amount) or 0
  if not enemyKey or not actorName or amount == 0 then return end
  self:RecordEnemyActivity(enemyKey, enemyName, timestamp)
  local actorThreat = self:GetOrCreateActorThreat(enemyKey, actorName, identity)
  actorThreat.threat = max(0, actorThreat.threat + amount)
end

function ThreatEstimator:GetExplicitSpellThreat(spellID)
  spellID = tonumber(spellID)
  if not spellID then return 0, 0 end
  local cachedThreat = self.explicitThreatBySpellID[spellID]
  if cachedThreat then return cachedThreat.target, cachedThreat.all end

  local spellEffects = readSpellRecordField(spellID, "effect")
  local spellBasePoints = readSpellRecordField(spellID, "effectBasePoints")
  local targetThreat, allThreat = 0, 0
  if type(spellEffects) == "table" and type(spellBasePoints) == "table" then
    local effectIndex, effectType, threatAmount
    for effectIndex = 1, 3 do
      effectType = tonumber(spellEffects[effectIndex])
      threatAmount = (tonumber(spellBasePoints[effectIndex]) or -1) + 1
      if effectType == SPELL_EFFECT_THREAT then
        targetThreat = targetThreat + threatAmount
      elseif effectType == SPELL_EFFECT_THREAT_ALL then
        allThreat = allThreat + threatAmount
      end
    end
  end

  self.explicitThreatBySpellID[spellID] = { target = targetThreat, all = allThreat }
  return targetThreat, allThreat
end

function ThreatEstimator:RecordSpellGo(spellID, casterGUID, targetGUID, targetsHit, timestamp)
  spellID = tonumber(spellID)
  local actorName, identity = self:GetActorByGUID(casterGUID)
  if not spellID or not actorName then return end
  local targetThreat, allThreat = self:GetExplicitSpellThreat(spellID)
  if targetThreat == 0 and allThreat == 0 then return end
  timestamp = timestamp or GetTime()

  if targetThreat ~= 0 and isUsableGUID(targetGUID) and (tonumber(targetsHit) or 1) > 0 then
    local targetName = UnitName and UnitName(targetGUID) or nil
    local enemyKey = self:ResolveEnemyKey(targetName, targetGUID)
    self:AddExplicitThreat(enemyKey, targetName, actorName, identity, targetThreat, timestamp)
  end

  if allThreat ~= 0 then
    local enemyKey, enemy
    for enemyKey, enemy in pairs(self.enemyByKey) do
      self:AddExplicitThreat(enemyKey, enemy.name, actorName, identity, allThreat, timestamp)
    end
  end
end

function ThreatEstimator:RemoveEnemy(identifier)
  if not identifier then return end

  local mappedKey = self.enemyKeyByName[identifier]
  if mappedKey then
    removeEnemyByKey(self, mappedKey)
    return
  end

  if self.enemyByKey[identifier] or self.threatByEnemyKey[identifier] then
    removeEnemyByKey(self, identifier)
    return
  end

  local enemyKey, enemy
  for enemyKey, enemy in pairs(self.enemyByKey) do
    if enemy.name == identifier then removeEnemyByKey(self, enemyKey) end
  end
end

local function sortThreatDescending(left, right)
  if left.threat == right.threat then return left.name < right.name end
  return left.threat > right.threat
end

function ThreatEstimator:Build(targetName, targetKey, output)
  output = output or {}
  local outputIndex
  for outputIndex = 1, table_getn(output) do output[outputIndex] = nil end

  local enemyKey = self:FindRecordedEnemyKey(targetName, targetKey)
  local enemyThreat = enemyKey and self.threatByEnemyKey[enemyKey]
  if not enemyThreat then return output, 0 end

  local actorName, actorThreat
  local outputCount = 0
  for actorName, actorThreat in pairs(enemyThreat) do
    if actorThreat.threat and actorThreat.threat > 0 then
      outputCount = outputCount + 1
      local outputEntry = output[outputCount] or {}
      outputEntry.name = actorName
      outputEntry.class = actorThreat.class or "OTHER"
      outputEntry.threat = actorThreat.threat
      outputEntry.melee = actorThreat.melee and true or false
      output[outputCount] = outputEntry
    end
  end
  table_sort(output, sortThreatDescending)
  if outputCount == 0 then return output, 0 end

  local highestThreat = output[1].threat
  for outputIndex = 1, outputCount do
    output[outputIndex].percent = highestThreat > 0 and output[outputIndex].threat / highestThreat * 100 or 0
    output[outputIndex].tank = outputIndex == 1
  end
  return output, outputCount
end

function ThreatEstimator:Reset()
  wipeTable(self.threatByEnemyKey)
  wipeTable(self.enemyByKey)
  wipeTable(self.enemyKeyByName)
end

Skada:Subscribe("damageRecorded", function(actorName, identity, targetName, amount, spellName, spellID, timestamp)
  ThreatEstimator:RecordDamage(actorName, identity, targetName, amount, spellName, spellID, timestamp)
end)
Skada:Subscribe("healingRecorded", function(actorName, identity, amount, timestamp)
  ThreatEstimator:RecordHealing(actorName, identity, amount, timestamp)
end)
Skada:Subscribe("unitDied", function(identifier) ThreatEstimator:RemoveEnemy(identifier) end)
Skada:Subscribe("combatStateChanged", function() ThreatEstimator:Reset() end)
Skada:Subscribe("dataReset", function() ThreatEstimator:Reset() end)

Skada:RegisterEvent("PLAYER_ENTERING_WORLD", function()
  ThreatEstimator:Reset()
  ThreatEstimator:ClearSpellMetadataCache()
end)
Skada:RegisterEvent("PLAYER_TARGET_CHANGED", function()
  if Skada.Data and Skada.Data.active then ThreatEstimator:ObserveCurrentEnemy(GetTime()) end
end)
Skada:RegisterEvent("UNIT_DIED", function(_, guid) ThreatEstimator:RemoveEnemy(guid) end)
Skada:RegisterEvent("SPELL_GO_SELF", function(_, _, spellID, casterGUID, targetGUID, _, targetsHit)
  ThreatEstimator:RecordSpellGo(spellID, casterGUID, targetGUID, targetsHit, GetTime())
end)
Skada:RegisterEvent("SPELL_GO_OTHER", function(_, _, spellID, casterGUID, targetGUID, _, targetsHit)
  ThreatEstimator:RecordSpellGo(spellID, casterGUID, targetGUID, targetsHit, GetTime())
end)
