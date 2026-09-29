local Skada = (_G or getfenv(0)).Skada

local ThreatEstimator = {
  threatByEnemyKey = {},
  enemyByKey = {},
  enemyCount = 0,
  enemyKeyByName = {},
  targetProbeName = nil,
  targetProbeGUID = nil,
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
local setmetatable = setmetatable

local ZERO_GUID_LONG = "0x0000000000000000"
local ZERO_GUID_SHORT = "0x000000000"
local NAME_PREFIX = "NAME:"
-- A mob that evades, despawns or dies without a death line never sends a
-- removal. After this long without damage or attention it stops counting as
-- a live enemy for the heal split, and its table and name mapping go with
-- it so a stale mapping cannot re-register it on a later hit.
local ENEMY_IDLE_SECONDS = 30

local entryPoolsByOutput = setmetatable({}, { __mode = "k" })

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

-- Real GUIDs ("0x" plus hex digits) are the only identifiers shaped nothing
-- like a mob name; a key shaped like this has no name path to walk.
local function isGUIDShaped(value)
  return type(value) == "string" and string_find(value, "^0x%x+$") ~= nil
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

-- The 1.12 client keeps a corpse on the target token and a hunter's pet can
-- carry a wild mob's species name, so a name match alone never picks a unit.
local function isLiveEnemyUnit(unitToken)
  if not UnitExists or not UnitExists(unitToken) then return false end
  if UnitIsDead and UnitIsDead(unitToken) then return false end
  if UnitIsPlayer and UnitIsPlayer(unitToken) then return false end
  if UnitCanAttack and not UnitCanAttack("player", unitToken) then return false end
  return true
end

-- The GUID of the unit on unitToken when it is a live enemy named enemyName.
local function liveEnemyGUIDOnToken(unitToken, enemyName)
  if not enemyName or not UnitName or not UnitGUID then return nil end
  if UnitName(unitToken) ~= enemyName or not isLiveEnemyUnit(unitToken) then return nil end
  local unitGUID = UnitGUID(unitToken)
  if isUsableGUID(unitGUID) then return unitGUID end
end

-- The one live-enemy guard, shared with the threat window's target checks.
function ThreatEstimator:IsLiveEnemyUnit(unitToken)
  return isLiveEnemyUnit(unitToken)
end

-- Calls visit(unitToken) for every token that can hold an enemy: the
-- player's own units first, then each groupmate's target. Stops when visit
-- returns true.
local function eachEnemyUnitToken(visit)
  local candidateIndex
  for candidateIndex = 1, table_getn(ENEMY_UNIT_CANDIDATES) do
    if visit(ENEMY_UNIT_CANDIDATES[candidateIndex]) then return true end
  end

  local groupTokens = Skada.Data and Skada.Data.groupTokens
  if not groupTokens then return false end
  local groupIndex, groupToken
  for groupIndex = 1, table_getn(groupTokens) do
    groupToken = groupTokens[groupIndex]
    if groupToken ~= "player" and visit(groupToken .. "target") then return true end
  end
  return false
end

local function findUnitGUIDByName(enemyName)
  local foundGUID
  if not UnitExists then return nil end
  eachEnemyUnitToken(function(unitToken)
    if UnitExists(unitToken) then foundGUID = liveEnemyGUIDOnToken(unitToken, enemyName) end
    return foundGUID ~= nil
  end)
  return foundGUID
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
  if estimator.enemyByKey[enemyKey] then
    estimator.enemyCount = max(0, (estimator.enemyCount or 0) - 1)
  end
  estimator.enemyByKey[enemyKey] = nil
  local enemyName, mappedKey
  for enemyName, mappedKey in pairs(estimator.enemyKeyByName) do
    if mappedKey == enemyKey then estimator.enemyKeyByName[enemyName] = nil end
  end
  -- The probe cache answers "the live mob on the target token". A removed
  -- key that matches it is a dead or gone mob, so only its name may stay
  -- cached; the GUID must never answer for it again.
  if estimator.targetProbeGUID == enemyKey then estimator.targetProbeGUID = nil end
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
  -- Two mobs can share a name (a pull of two Boars). Repointing the name at
  -- the new GUID keeps the other mob's table intact, so switching back shows
  -- its threat instead of an empty window.
  local nameKey = NAME_PREFIX .. enemyName
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
    if enemy then self.enemyCount = max(0, (self.enemyCount or 0) - 1) end
    self.enemyByKey[nameKey] = nil
  end
  self.enemyKeyByName[enemyName] = enemyGUID
end

-- A chat line names the enemy only. For the player's own hits the live
-- target may stand in for the name (a corpse or a same-named pet on the
-- token never qualifies), but a groupmate's line must not: it may be naming
-- a different mob than the one the player is looking at. The probe answer
-- is cached and refreshed on target changes and removals, so once the
-- target is known an own hit costs no unit calls.
function ThreatEstimator:ResolveEnemyKey(enemyName, knownGUID, ownHit)
  enemyName = trim(enemyName)
  if isUsableGUID(knownGUID) then
    self:PromoteEnemyNameToGUID(enemyName, knownGUID)
    return knownGUID
  end

  if not enemyName then return nil end
  local cachedKey = self.enemyKeyByName[enemyName]

  local targetGUID
  if ownHit then
    if self.targetProbeName == enemyName and self.targetProbeGUID then
      targetGUID = self.targetProbeGUID
    else
      targetGUID = liveEnemyGUIDOnToken("target", enemyName)
    end
  end
  if targetGUID then
    if cachedKey ~= targetGUID then self:PromoteEnemyNameToGUID(enemyName, targetGUID) end
    return targetGUID
  end

  if cachedKey then return cachedKey end

  local discoveredGUID = findUnitGUIDByName(enemyName)
  if isUsableGUID(discoveredGUID) then
    self:PromoteEnemyNameToGUID(enemyName, discoveredGUID)
    return discoveredGUID
  end

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
    self.enemyCount = (self.enemyCount or 0) + 1
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

-- An expired enemy leaves the whole estimate: the count that splits heal
-- threat, its threat table and its name mapping. A stale mapping would
-- re-register the mob on the next hit, and a name-only death could no
-- longer match it.
function ThreatEstimator:ExpireIdleEnemies(now)
  if not now then return end
  local enemyKey, enemy
  for enemyKey, enemy in pairs(self.enemyByKey) do
    if enemy.lastSeen and now - enemy.lastSeen > ENEMY_IDLE_SECONDS then
      removeEnemyByKey(self, enemyKey)
    end
  end
end

-- targetGUID is the exact unit when the Nampower packet path supplied one;
-- chat lines carry a name only and fall back to the target heuristic. That
-- heuristic is the player's own: a line from anyone else names a mob the
-- player may not be looking at. Pets merge into the player upstream, so the
-- player's name covers the whole "own hits" set.
function ThreatEstimator:RecordDamage(actorName, identity, targetName, amount, spellName, spellID, timestamp, targetGUID)
  amount = tonumber(amount) or 0
  if not actorName or not targetName or amount <= 0 then return end
  local ownHit = actorName == (Skada.Data and Skada.Data:GetPlayerName() or nil)
  local enemyKey = self:ResolveEnemyKey(targetName, targetGUID, ownHit)
  if not enemyKey then return end
  self:RecordEnemyActivity(enemyKey, targetName, timestamp)
  local actorThreat = self:GetOrCreateActorThreat(enemyKey, actorName, identity)
  actorThreat.threat = actorThreat.threat + amount * self:GetDamageMultiplier(spellName, spellID)
  if spellName and (spellName == "Auto Attack" or string_find(spellName, "Auto Attack", 1, true)) then
    actorThreat.melee = true
  end
end

-- The heal split observes the mob on the target token so a fight where the
-- player never swings still splits against the right enemy; the probe cache
-- is refreshed here for the same reason.
function ThreatEstimator:ObserveCurrentEnemy(timestamp)
  self:ProbeTargetToken()
  if not self.targetProbeName then return end
  local enemyKey = self:ResolveEnemyKey(self.targetProbeName, self.targetProbeGUID, true)
  self:RecordEnemyActivity(enemyKey, self.targetProbeName, timestamp)
end

-- Caches what the target token currently holds when it is a live enemy. Own
-- damage lines resolve against this instead of re-probing the token, and
-- PLAYER_TARGET_CHANGED refreshes it the moment the token changes.
function ThreatEstimator:ProbeTargetToken()
  self.targetProbeName, self.targetProbeGUID = nil, nil
  if not UnitName or not isLiveEnemyUnit("target") then return end
  local enemyName = UnitName("target")
  local enemyGUID = UnitGUID and UnitGUID("target") or nil
  if not enemyName or enemyName == "" or not isUsableGUID(enemyGUID) then return end
  self.targetProbeName = enemyName
  self.targetProbeGUID = enemyGUID
end

function ThreatEstimator:RecordHealing(actorName, identity, amount, timestamp)
  amount = tonumber(amount) or 0
  if not actorName or amount <= 0 then return end
  self:ObserveCurrentEnemy(timestamp)
  self:ExpireIdleEnemies(timestamp)

  local enemyCount = self.enemyCount or 0
  local enemyKey
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
    self:ExpireIdleEnemies(timestamp)
    local enemyKey, enemy
    for enemyKey, enemy in pairs(self.enemyByKey) do
      self:AddExplicitThreat(enemyKey, enemy.name, actorName, identity, allThreat, timestamp)
    end
  end
end

function ThreatEstimator:IsTrackedKey(enemyKey)
  return enemyKey ~= nil and (self.enemyByKey[enemyKey] ~= nil or self.threatByEnemyKey[enemyKey] ~= nil)
end

-- identifier is a GUID from UNIT_DIED or a bare name from a "X dies." line;
-- deathGUID is the exact unit when the Nampower death packet carried one.
-- A name-only death cannot say which of two same-named mobs fell. A dead
-- target carrying the name is the one that fell and only its table goes.
-- Otherwise every same-named mob still alive on a unit token (the target,
-- a groupmate's target, focus, mouseover) keeps its table and the rest go;
-- with no such mob in sight, every table under the name goes.
function ThreatEstimator:RemoveEnemy(identifier, deathGUID)
  if not identifier then return end

  if isUsableGUID(deathGUID) then
    removeEnemyByKey(self, deathGUID)
    removeEnemyByKey(self, NAME_PREFIX .. identifier)
    return
  end

  -- A GUID carries no name to match tokens with: remove it by key and stop
  -- instead of sweeping every token for a mob "named" 0x....
  if isGUIDShaped(identifier) then
    removeEnemyByKey(self, identifier)
    return
  end

  if self:IsTrackedKey(identifier) then
    removeEnemyByKey(self, identifier)
    return
  end

  if UnitExists and UnitExists("target") and UnitName and UnitName("target") == identifier
    and UnitIsDead and UnitIsDead("target") then
    local corpseGUID = UnitGUID and UnitGUID("target")
    if isUsableGUID(corpseGUID) then
      -- The corpse is the mob that fell even when nothing was ever tracked
      -- under its GUID: stopping here keeps the survivor search below from
      -- sweeping out a live same-named twin tracked elsewhere.
      removeEnemyByKey(self, corpseGUID)
      removeEnemyByKey(self, NAME_PREFIX .. identifier)
      return
    end
  end

  local survivorByKey = {}
  eachEnemyUnitToken(function(unitToken)
    local liveGUID = liveEnemyGUIDOnToken(unitToken, identifier)
    if liveGUID and self:IsTrackedKey(liveGUID) then survivorByKey[liveGUID] = true end
  end)

  local mappedKey = self.enemyKeyByName[identifier]
  if mappedKey and not survivorByKey[mappedKey] then removeEnemyByKey(self, mappedKey) end
  local enemyKey, enemy
  for enemyKey, enemy in pairs(self.enemyByKey) do
    if enemy.name == identifier and not survivorByKey[enemyKey] then removeEnemyByKey(self, enemyKey) end
  end
  removeEnemyByKey(self, NAME_PREFIX .. identifier)

  local targetSurvivor = liveEnemyGUIDOnToken("target", identifier)
  if targetSurvivor and survivorByKey[targetSurvivor] then self.enemyKeyByName[identifier] = targetSurvivor end
end

function ThreatEstimator:PruneActors(keepPredicate)
  if not keepPredicate then return end
  local enemyKey, enemyThreat, actorName
  for enemyKey, enemyThreat in pairs(self.threatByEnemyKey) do
    for actorName in pairs(enemyThreat) do
      if not keepPredicate(actorName) then enemyThreat[actorName] = nil end
    end
  end
end

local function sortThreatDescending(left, right)
  if left.threat == right.threat then return left.name < right.name end
  return left.threat > right.threat
end

function ThreatEstimator:Build(targetName, targetKey, output)
  output = output or {}
  local pool = entryPoolsByOutput[output]
  if not pool then
    pool = {}
    entryPoolsByOutput[output] = pool
  end
  local outputIndex
  for outputIndex = 1, table_getn(output) do output[outputIndex] = nil end
  if table.setn then table.setn(output, 0) end

  local enemyKey = self:FindRecordedEnemyKey(targetName, targetKey)
  local enemyThreat = enemyKey and self.threatByEnemyKey[enemyKey]
  if not enemyThreat then return output, 0 end

  local actorName, actorThreat
  local outputCount = 0
  for actorName, actorThreat in pairs(enemyThreat) do
    if actorThreat.threat and actorThreat.threat > 0 then
      outputCount = outputCount + 1
      local outputEntry = pool[outputCount]
      if not outputEntry then
        outputEntry = {}
        pool[outputCount] = outputEntry
      end
      outputEntry.name = actorName
      outputEntry.class = actorThreat.class or "OTHER"
      outputEntry.threat = actorThreat.threat
      outputEntry.melee = actorThreat.melee and true or false
      output[outputCount] = outputEntry
    end
  end
  if table.setn then table.setn(output, outputCount) end
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
  self.enemyCount = 0
  self.targetProbeName, self.targetProbeGUID = nil, nil
end

Skada:Subscribe("damageRecorded", function(actorName, identity, targetName, amount, spellName, spellID, timestamp, targetGUID)
  ThreatEstimator:RecordDamage(actorName, identity, targetName, amount, spellName, spellID, timestamp, targetGUID)
end)
Skada:Subscribe("healingRecorded", function(actorName, identity, amount, timestamp)
  ThreatEstimator:RecordHealing(actorName, identity, amount, timestamp)
end)
Skada:Subscribe("unitDied", function(unitName, unitGUID) ThreatEstimator:RemoveEnemy(unitName, unitGUID) end)
Skada:Subscribe("combatStateChanged", function() ThreatEstimator:Reset() end)
Skada:Subscribe("dataReset", function() ThreatEstimator:Reset() end)

Skada:RegisterEvent("PLAYER_ENTERING_WORLD", function()
  ThreatEstimator:Reset()
  ThreatEstimator:ClearSpellMetadataCache()
end)
Skada:RegisterEvent("PLAYER_TARGET_CHANGED", function()
  ThreatEstimator:ProbeTargetToken()
  if Skada.Data and Skada.Data.active then ThreatEstimator:ObserveCurrentEnemy(GetTime()) end
end)
-- Nampower's events never reach the shared frame: its registration is gated
-- on C_EventUtils.IsEventValid, which does not know Nampower's codes. The
-- ingest owns the only frame that hears them and republishes spell-go on the
-- bus; deaths already arrive as unitDied above.
Skada:Subscribe("spellGo", function(spellID, casterGUID, targetGUID, targetsHit, timestamp)
  ThreatEstimator:RecordSpellGo(spellID, casterGUID, targetGUID, targetsHit, timestamp)
end)
