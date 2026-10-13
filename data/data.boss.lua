local Skada = (_G or getfenv(0)).Skada

local BossDetection = {}
Skada.BossDetection = BossDetection

local type = type
local pairs = pairs
local pcall = pcall
local table_getn = SkadaCompat.Table.getn
local table_insert = SkadaCompat.Table.insert
local string_find = string.find

-- The per-second trash-pull scan probes every group member's target.
-- Both API calls below are deterministic per key (GUID → creature ID,
-- creature ID → info), so each is worth a cache; without one the 1 Hz
-- Find over ~40 engaged units issued ~80 raw API probes every second
-- for the duration of every pull. A GUID without a creature ID is cached as
-- false (the ID is read from the GUID itself, so the answer never changes);
-- creature info that is not available yet is asked again next poll, since
-- the client fills its creature cache asynchronously.
-- The tables are strong (weak values would empty the info cache on every
-- collection) and dropped wholesale once a bound is reached, so GUIDs
-- from hours of churning targets cannot pile up.
local creatureIDsByGUID = Skada.Common.NewBoundedMap(2048)
local creatureInfoByID = Skada.Common.NewBoundedMap(2048)
local function getCreatureRecord(unitToken)
  if not C_CreatureInfo or not C_CreatureInfo.GetCreatureID or not UnitGUID then return end
  local unitGUID = UnitGUID(unitToken)
  if not unitGUID then return end

  local creatureID = creatureIDsByGUID.entries[unitGUID]
  if creatureID == nil then
    creatureID = C_CreatureInfo.GetCreatureID(unitGUID) or false
    creatureIDsByGUID:Set(unitGUID, creatureID)
  end
  if not creatureID then return end

  local creatureInfo = creatureInfoByID.entries[creatureID]
  if not creatureInfo and C_CreatureInfo.GetCreatureInfoByID then
    creatureInfo = C_CreatureInfo.GetCreatureInfoByID(creatureID)
    creatureInfoByID:Set(creatureID, creatureInfo)
  end
  return creatureID, creatureInfo
end

local function hasBossCompletionOption(module)
  if type(module) ~= "table" or module.trashMod or not module.bossSync then return false end
  if type(module.toggleoptions) ~= "table" then return false end

  local _, optionName
  for _, optionName in pairs(module.toggleoptions) do
    if optionName == "bosskill" then return true end
  end
  return false
end

local function addNamesToSet(nameSet, names)
  if type(names) == "string" then
    nameSet[names] = true
    return
  end
  if type(names) ~= "table" then return end

  local _, name
  for _, name in pairs(names) do
    if type(name) == "string" then nameSet[name] = true end
  end
end

local function mapEncounterTriggers(encounterNameByTrigger, triggerNames, excludedNames, encounterName)
  if type(triggerNames) == "string" then
    if not excludedNames[triggerNames] then encounterNameByTrigger[triggerNames] = encounterName end
    return
  end
  if type(triggerNames) ~= "table" then return end

  local _, triggerName
  for _, triggerName in pairs(triggerNames) do
    if type(triggerName) == "string" and not excludedNames[triggerName] then
      encounterNameByTrigger[triggerName] = encounterName
    end
  end
end

local BIGWIGS_RETRY_DELAY = 30

local function buildBigWigsEncounterCache(bigWigs)
  local encounterModules = {}
  local encounterNameByTrigger = {}
  local _, module
  for _, module in bigWigs:IterateModules() do
    if hasBossCompletionOption(module) then
      table_insert(encounterModules, module)
      local encounterName = module.translatedName or module.bossSync
      local excludedNames = {}
      addNamesToSet(excludedNames, module.wipemobs)
      mapEncounterTriggers(encounterNameByTrigger, module.enabletrigger, excludedNames, encounterName)
    end
  end
  return encounterModules, encounterNameByTrigger
end

function BossDetection:ClearBigWigsCache()
  self.bigWigsCore = nil
  self.bigWigsEncounterModules = nil
  self.bigWigsEncounterNameByTrigger = nil
  self.bigWigsFailedCore = nil
end

function BossDetection:LoadBigWigsEncounterCache(bigWigs)
  if self.bigWigsCore == bigWigs and self.bigWigsEncounterModules then
    return self.bigWigsEncounterModules, self.bigWigsEncounterNameByTrigger
  end
  -- A failed build waits out a backoff before the next try, so a broken
  -- module does not rerun the full module walk every poll of a pull, and a
  -- one-off failure (a module still registering) does not switch BigWigs
  -- detection off for the rest of the session. A BigWigs load retries at once.
  local now = GetTime()
  if self.bigWigsFailedCore == bigWigs and now < self.bigWigsRetryAt then return end

  local succeeded, encounterModules, encounterNameByTrigger = pcall(buildBigWigsEncounterCache, bigWigs)
  if not succeeded then
    self.bigWigsFailedCore = bigWigs
    self.bigWigsRetryAt = now + BIGWIGS_RETRY_DELAY
    return
  end
  self.bigWigsFailedCore = nil

  self.bigWigsCore = bigWigs
  self.bigWigsEncounterModules = encounterModules
  self.bigWigsEncounterNameByTrigger = encounterNameByTrigger
  return encounterModules, encounterNameByTrigger
end

function BossDetection:GetBigWigsEncounters()
  local bigWigs = _G.BigWigs
  if type(bigWigs) ~= "table" or type(bigWigs.IterateModules) ~= "function" then return end

  local encounterModules, encounterNameByTrigger = self:LoadBigWigsEncounterCache(bigWigs)
  if not encounterModules then return end

  local moduleIndex, module
  for moduleIndex = 1, table_getn(encounterModules) do
    module = encounterModules[moduleIndex]
    if module.engaged then return module.translatedName or module.bossSync, encounterNameByTrigger end
  end
  return nil, encounterNameByTrigger
end

function BossDetection:InspectUnit(unitToken, encounterNameByTrigger)
  if not UnitExists or not UnitExists(unitToken) then return end
  if UnitIsPlayer and UnitIsPlayer(unitToken) then return end
  -- A hunter pet can be renamed "Onyxia"; player-controlled units never
  -- stand for an encounter, whatever their name.
  if UnitPlayerControlled and UnitPlayerControlled(unitToken) then return end
  if UnitAffectingCombat and not UnitAffectingCombat(unitToken) then return end

  local unitName = UnitName(unitToken)
  if not unitName then return end

  local creatureID, creatureInfo = getCreatureRecord(unitToken)
  local encounterName = encounterNameByTrigger and encounterNameByTrigger[unitName]
  if encounterName then return encounterName, creatureID end
  if creatureInfo and creatureInfo.rank == 3 then return unitName, creatureID end
  if UnitClassification and UnitClassification(unitToken) == "worldboss" then return unitName, creatureID end
end

function BossDetection:Find(groupTokens)
  local engagedEncounterName, encounterNameByTrigger = self:GetBigWigsEncounters()
  if engagedEncounterName then return engagedEncounterName end

  local encounterName, creatureID = self:InspectUnit("target", encounterNameByTrigger)
  if encounterName then return encounterName, creatureID end

  local groupIndex, groupToken
  for groupIndex = 1, table_getn(groupTokens) do
    groupToken = groupTokens[groupIndex]
    if groupToken ~= "player" and not string_find(groupToken, "pet", 1, true) then
      encounterName, creatureID = self:InspectUnit(groupToken .. "target", encounterNameByTrigger)
      if encounterName then return encounterName, creatureID end
    end
  end
end

local function handleAddOnLoaded(eventName, loadedAddOnName)
  if loadedAddOnName == "BigWigs" then
    BossDetection:ClearBigWigsCache()
  elseif GetAddOnMetadata and GetAddOnMetadata(loadedAddOnName, "X-BigWigsModule") then
    BossDetection:ClearBigWigsCache()
  end
end

Skada:RegisterEvent("ADDON_LOADED", handleAddOnLoaded)
