local Skada = (_G or getfenv(0)).Skada

local AuraScanner = {}
Skada.AuraScanner = AuraScanner

local Common = Skada.Common
local wipeTable = Common.Wipe

local pairs = pairs
local min = math.min
local max = math.max
local table_getn = table.getn
local table_insert = table.insert
local table_remove = table.remove

function AuraScanner:QueueAuraBaseline(unit, unknownOnly, now)
  if not self.auraAPI or not unit or not UnitExists(unit) then return end
  if unknownOnly then
    local guid = UnitGUID(unit)
    local seen = guid and self.auraCacheSeen[guid]
    if seen and (not now or now - seen <= 120) then return end
  end
  if self.pendingAuraBaselineUnits[unit] then return end
  self.pendingAuraBaselineUnits[unit] = true
  table_insert(self.pendingAuraBaselines, unit)
end

function AuraScanner:DrainAuraBaselines(now, budget)
  local queue = self.pendingAuraBaselines
  local queued = self.pendingAuraBaselineUnits
  local scanned = 0
  while scanned < (budget or 1) and table_getn(queue) > 0 do
    local unit = table_remove(queue)
    if queued[unit] then
      queued[unit] = nil
      self:ScanAll(unit, false, now)
      scanned = scanned + 1
    end
  end
end

function AuraScanner:SnapshotAuras(unit, friendly, includeAll)
  if not self.auraAPI or not unit or not UnitExists(unit) then return nil end
  local snapshot = {}
  local filter
  if friendly then
    filter = includeAll and "HARMFUL" or "HARMFUL|DISPELLABLE"
  else
    filter = includeAll and "HELPFUL" or "HELPFUL|DISPELLABLE"
  end

  local auraSlotIndex = 1
  while true do
    local name, _, _, _, _, _, _, _, _, spellID = C_UnitAuras.UnitAura(unit, auraSlotIndex, filter)
    if not name then break end
    snapshot[spellID or name] = name
    auraSlotIndex = auraSlotIndex + 1
  end
  return snapshot
end

function AuraScanner:GetAuraSource(unit, spellID, filter)
  local aura = C_UnitAuras.GetUnitAuraBySpellID(unit, spellID, filter or "HARMFUL")
  if not aura then return nil, nil end
  local sourceGUID = aura.sourceGUID
  local sourceName
  if aura.sourceUnit and UnitExists(aura.sourceUnit) then
    sourceName = UnitName(aura.sourceUnit)
    sourceGUID = sourceGUID or UnitGUID(aura.sourceUnit)
  elseif sourceGUID then
    local identity = Skada.Data:GetIdentityByGUID(sourceGUID)
    sourceName = identity and identity.name
    if not sourceName and UnitNameFromGUID then sourceName = UnitNameFromGUID(sourceGUID) end
  end
  return sourceName, sourceGUID
end

function AuraScanner:ScanCC(unit, recordNew, now, targetGUID, targetName)
  if not self.auraAPI or not unit then return end
  if not targetGUID then
    if not UnitExists(unit) then return end
    targetGUID = UnitGUID(unit)
  end
  if not targetGUID then return end
  now = now or GetTime()
  self.auraCacheSeen[targetGUID] = now
  self.guidByToken[unit] = targetGUID
  Skada.Data:AddObservedUnit(unit, false)

  local cache = self.ccByTarget[targetGUID]
  if not cache then
    cache = {}
    self.ccByTarget[targetGUID] = cache
  end
  wipeTable(self.seenAuras)

  targetName = targetName or UnitName(unit)
  local auraSlotIndex = 1
  while true do
    local auraName, _, _, _, duration, expirationTime, _, _, _, spellID =
      C_UnitAuras.UnitAura(unit, auraSlotIndex, "HARMFUL|CROWD_CONTROL")
    if not auraName then break end
    local key = spellID or auraName
    self.seenAuras[key] = true
    if not cache[key] then
      local sourceName, sourceGUID = self:GetAuraSource(unit, spellID)
      cache[key] = {
        name = auraName,
        spellID = spellID,
        sourceName = sourceName,
        sourceGUID = sourceGUID,
        targetName = targetName,
        startTime = now,
        duration = duration or 0,
        expirationTime = expirationTime or 0,
      }
      if recordNew and sourceName then
        Skada.Data:RecordCC(sourceName, targetName, auraName, spellID, now)
      end
      self.ccGuidByName[targetName] = targetGUID
    else
      cache[key].expirationTime = expirationTime or cache[key].expirationTime
      cache[key].duration = duration or cache[key].duration
    end
    auraSlotIndex = auraSlotIndex + 1
  end

  local key, entry, removedName
  for key, entry in pairs(cache) do
    if not self.seenAuras[key] then
      local observed = max(0, now - entry.startTime)
      if entry.duration and entry.duration > 0 then observed = min(observed, entry.duration) end
      if entry.sourceName then
        Skada.Data:RecordCCDuration(entry.sourceName, entry.name, entry.spellID, observed)
      end

      local damage = self.lastDamageByTarget[targetGUID]
      if recordNew and damage and now - damage.time <= 0.35 and
         entry.expirationTime and entry.expirationTime > now + 0.20 then
        Skada.Data:RecordCCBreak(damage.sourceName, entry.targetName, entry.name, entry.spellID, now)
      end
      cache[key] = nil
      removedName = entry.targetName
    end
  end
  if removedName and next(cache) == nil and self.ccGuidByName[removedName] == targetGUID then
    self.ccGuidByName[removedName] = nil
  end
end

function AuraScanner:ScanAuraKind(unit, filter, cacheStore, isBuff, recordNew, now, targetGUID, targetName)
  if not self.auraAPI or not unit then return end
  if not targetGUID then
    if not UnitExists(unit) then return end
    targetGUID = UnitGUID(unit)
  end
  if not targetGUID then return end
  now = now or GetTime()
  self.auraCacheSeen[targetGUID] = now

  local cache = cacheStore[targetGUID]
  if not cache then
    cache = {}
    cacheStore[targetGUID] = cache
  end
  wipeTable(self.seenAuraKind)

  targetName = targetName or UnitName(unit)
  local auraSlotIndex = 1
  while true do
    local auraName, _, _, _, duration, expirationTime, _, _, _, spellID = C_UnitAuras.UnitAura(unit, auraSlotIndex, filter)
    if not auraName then break end
    local key = spellID or auraName
    self.seenAuraKind[key] = true
    if not cache[key] then
      local sourceName, sourceGUID = self:GetAuraSource(unit, spellID, isBuff and "HELPFUL" or "HARMFUL")
      if isBuff and not sourceName then sourceName = targetName end
      cache[key] = {
        name = auraName,
        spellID = spellID,
        sourceName = sourceName,
        sourceGUID = sourceGUID,
        targetName = targetName,
        startTime = now,
        duration = duration or 0,
        expirationTime = expirationTime or 0,
      }
      if recordNew and sourceName then
        if isBuff then
          Skada.Data:RecordBuff(sourceName, targetName, auraName, spellID, now)
        else
          Skada.Data:RecordDebuff(sourceName, targetName, auraName, spellID, now)
        end
      end
    else
      cache[key].expirationTime = expirationTime or cache[key].expirationTime
      cache[key].duration = duration or cache[key].duration
    end
    auraSlotIndex = auraSlotIndex + 1
  end

  local key, entry
  for key, entry in pairs(cache) do
    if not self.seenAuraKind[key] then
      local observed = max(0, now - entry.startTime)
      if entry.duration and entry.duration > 0 then observed = min(observed, entry.duration) end
      if entry.sourceName then
        if isBuff then
          Skada.Data:RecordBuffDuration(entry.sourceName, entry.name, entry.spellID, observed)
        else
          Skada.Data:RecordDebuffDuration(entry.sourceName, entry.name, entry.spellID, observed)
        end
      end
      cache[key] = nil
    end
  end
end

function AuraScanner:ScanAll(unit, recordNew, now, recordBuffs)
  if not self.auraAPI or not unit or not UnitExists(unit) then return end
  self.pendingAuraBaselineUnits[unit] = nil
  local targetGUID = UnitGUID(unit)
  if not targetGUID then return end
  local targetName = UnitName(unit)
  self:ScanCC(unit, recordNew, now, targetGUID, targetName)
  self:ScanAuraKind(unit, "HARMFUL", self.debuffsByTarget, false, recordNew, now, targetGUID, targetName)
  self:ScanAuraKind(unit, "HELPFUL", self.buffsByTarget, true,
    recordNew and recordBuffs ~= false, now, targetGUID, targetName)
end

function AuraScanner:DrainDirtyAuras(now, budget)
  local queue = self.dirtyAuraQueue
  local dirty = self.dirtyAuraUnits
  if not (Skada.Data and Skada.Data.active) then
    while table_getn(queue) > 0 do
      local unit = table_remove(queue)
      if dirty[unit] then
        dirty[unit] = nil
        self:QueueAuraBaseline(unit)
      end
    end
    return
  end
  local scanned = 0
  while scanned < (budget or 1) and table_getn(queue) > 0 do
    local unit = table_remove(queue, 1)
    if dirty[unit] then
      dirty[unit] = nil
      if UnitExists(unit) then
        if self.pendingAuraBaselineUnits[unit] then
          self:ScanAll(unit, true, now, false)
        else
          self:ScanAll(unit, true, now)
        end
      end
      scanned = scanned + 1
    end
  end
end

local function flushAuraCache(store, guid, recordDuration, now)
  local cache = store[guid]
  if not cache then return end
  local _, entry
  for _, entry in pairs(cache) do
    local observed = max(0, now - entry.startTime)
    if entry.duration and entry.duration > 0 then observed = min(observed, entry.duration) end
    if entry.sourceName then recordDuration(entry.sourceName, entry.name, entry.spellID, observed) end
  end
  store[guid] = nil
end

function AuraScanner:ClearCCForToken(unit, now)
  local guid = self.guidByToken[unit]
  if not guid then return end
  local ccCache = self.ccByTarget[guid]
  local _, entry
  if ccCache then _, entry = next(ccCache) end
  local ccTargetName = entry and entry.targetName
  flushAuraCache(self.ccByTarget, guid, function(sourceName, name, spellID, observed)
    Skada.Data:RecordCCDuration(sourceName, name, spellID, observed)
  end, now)
  flushAuraCache(self.debuffsByTarget, guid, function(sourceName, name, spellID, observed)
    Skada.Data:RecordDebuffDuration(sourceName, name, spellID, observed)
  end, now)
  flushAuraCache(self.buffsByTarget, guid, function(sourceName, name, spellID, observed)
    Skada.Data:RecordBuffDuration(sourceName, name, spellID, observed)
  end, now)
  if ccTargetName and self.ccGuidByName[ccTargetName] == guid then
    self.ccGuidByName[ccTargetName] = nil
  end
  self.guidByToken[unit] = nil
end

function AuraScanner:OnUnitAura(unit)
  if not unit then return end
  local active = Skada.Data and Skada.Data.active
  local now
  if active then
    now = GetTime()
    if not self.dirtyAuraUnits[unit] then
      self.dirtyAuraUnits[unit] = true
      table_insert(self.dirtyAuraQueue, unit)
    end
  else
    self:QueueAuraBaseline(unit)
  end

  if table_getn(self.pendingDispels) == 0 then return end
  now = now or GetTime()
  local dispelIndex
  for dispelIndex = table_getn(self.pendingDispels), 1, -1 do
    local pending = self.pendingDispels[dispelIndex]
    if pending.targetUnit == unit and self:ResolveDispelSnapshot(pending, now) then
      table_remove(self.pendingDispels, dispelIndex)
    end
  end
end

Skada:RegisterEvent("UNIT_AURA", function(eventName, unit)
  local tracking = Skada.Tracking
  if tracking then tracking:OnUnitAura(unit) end
end)
Skada:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(eventName, unit)
  local tracking = Skada.Tracking
  if not tracking then return end
  if Skada.Data.active then
    tracking:ScanAll(unit, false, GetTime())
  else
    tracking:QueueAuraBaseline(unit)
  end
end)
Skada:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(eventName, unit)
  local tracking = Skada.Tracking
  if tracking then tracking:ClearCCForToken(unit, GetTime()) end
end)
Skada:RegisterEvent("PLAYER_TARGET_CHANGED", function()
  local tracking = Skada.Tracking
  if not tracking then return end
  if Skada.Data.active then
    tracking:ScanAll("target", false, GetTime())
  else
    tracking:QueueAuraBaseline("target")
  end
end)
Skada:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
  local tracking = Skada.Tracking
  if not tracking then return end
  if Skada.Data.active then
    tracking:ScanAll("focus", false, GetTime())
  else
    tracking:QueueAuraBaseline("focus")
  end
end)
