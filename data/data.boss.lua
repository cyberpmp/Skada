local Skada = (_G or getfenv(0)).Skada

local BossDetection = {}
Skada.BossDetection = BossDetection

local type = type
local pairs = pairs
local pcall = pcall
local table_getn = table.getn
local table_insert = table.insert
local string_find = string.find

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
end

function BossDetection:LoadBigWigsEncounterCache(bigWigs)
  if self.bigWigsCore == bigWigs and self.bigWigsEncounterModules then
    return self.bigWigsEncounterModules, self.bigWigsEncounterNameByTrigger
  end

  local succeeded, encounterModules, encounterNameByTrigger = pcall(buildBigWigsEncounterCache, bigWigs)
  if not succeeded then return end

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

local function getCreatureRecord(unitToken)
  if not C_CreatureInfo or not C_CreatureInfo.GetCreatureID or not UnitGUID then return end
  local unitGUID = UnitGUID(unitToken)
  if not unitGUID then return end

  local creatureID = C_CreatureInfo.GetCreatureID(unitGUID)
  local creatureInfo = creatureID and C_CreatureInfo.GetCreatureInfoByID
    and C_CreatureInfo.GetCreatureInfoByID(creatureID)
  return creatureID, creatureInfo
end

function BossDetection:InspectUnit(unitToken, encounterNameByTrigger)
  if not UnitExists or not UnitExists(unitToken) then return end
  if UnitIsPlayer and UnitIsPlayer(unitToken) then return end
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
