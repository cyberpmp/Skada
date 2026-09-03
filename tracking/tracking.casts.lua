local Skada = (_G or getfenv(0)).Skada

local CastTracker = {}
Skada.CastTracker = CastTracker

local type = type
local pairs = pairs
local table_getn = table.getn
local table_insert = table.insert
local table_remove = table.remove

local dispelCasts = {
  [527] = 1, [988] = 2,
  [528] = 1, [552] = 1,
  [1152] = 1, [4987] = 1,
  [370] = 1, [8012] = 2,
  [526] = 1, [2870] = 1,
  [2782] = 1, [8946] = 1, [2893] = 1,
  [475] = 1,
  [19505] = 1, [19731] = 1, [19734] = 1,
  [19736] = 1,
  [19801] = 1,
}

function CastTracker:NewDispelPending(sourceName, targetName, abilityName, spellID, before, now)
  local maximum = dispelCasts[spellID]
  if not maximum then return end
  local targetUnit = self:FindTargetUnit(targetName)
  local targetGUID = targetUnit and UnitGUID(targetUnit) or nil
  local friendly = targetUnit and UnitIsFriend("player", targetUnit) and true or false
  local includeAll = spellID == 19801
  if not before and targetUnit then
    before = self:SnapshotAuras(targetUnit, friendly, includeAll)
  end

  table_insert(self.pendingDispels, {
    sourceName = sourceName,
    targetName = targetName,
    targetUnit = targetUnit,
    targetGUID = targetGUID,
    abilityName = abilityName,
    spellID = spellID,
    maximum = maximum,
    count = 0,
    before = before,
    friendly = friendly,
    includeAll = includeAll,
    ready = now + 0.08,
    expires = now + 1.2,
  })
end

function CastTracker:RecordDispel(pending, auraName, auraID, now)
  local key = (pending.sourceName or "?") .. "\031" .. (pending.targetName or "?") .. "\031" .. (auraName or "?")
  if self.lastDispelKey == key and now - self.lastDispelTime < 0.75 then return false end
  self.lastDispelKey = key
  self.lastDispelTime = now
  pending.count = pending.count + 1
  Skada.Data:RecordDispel(pending.sourceName, pending.targetName, pending.abilityName, auraName, auraID, now)
  return true
end

function CastTracker:ResolveDispelSnapshot(pending, now)
  if not pending.before or not pending.targetUnit or not UnitExists(pending.targetUnit) then return false end
  if pending.targetGUID and UnitGUID(pending.targetUnit) ~= pending.targetGUID then return false end
  if not pending.targetGUID and pending.targetName and UnitName(pending.targetUnit) ~= pending.targetName then return false end
  local current = self:SnapshotAuras(pending.targetUnit, pending.friendly, pending.includeAll)
  if not current then return false end

  local auraID, auraName
  for auraID, auraName in pairs(pending.before) do
    if not current[auraID] and pending.count < pending.maximum then
      self:RecordDispel(pending, auraName, type(auraID) == "number" and auraID or nil, now)
    end
  end
  pending.before = current
  return pending.count >= pending.maximum
end

function CastTracker:RecordRawDispel(targetName, auraName, now)
  now = now or GetTime()
  local dispelIndex
  for dispelIndex = table_getn(self.pendingDispels), 1, -1 do
    local pending = self.pendingDispels[dispelIndex]
    if now <= pending.expires and (not pending.targetName or pending.targetName == targetName) then
      local auraID
      if pending.before then
        local spellId, name
        for spellId, name in pairs(pending.before) do
          if name == auraName then auraID = type(spellId) == "number" and spellId or nil break end
        end
      end
      self:RecordDispel(pending, auraName, auraID, now)
      if pending.count >= pending.maximum then table_remove(self.pendingDispels, dispelIndex) end
      return true
    end
  end
end

function CastTracker:RecordInterrupt(sourceName, targetName, abilityName, interruptedName, spellID, now)
  now = now or GetTime()
  local key = (sourceName or "?") .. "\031" .. (targetName or "?") .. "\031" .. (interruptedName or "?")
  if self.lastInterruptKey == key and now - self.lastInterruptTime < 0.75 then return false end
  self.lastInterruptKey = key
  self.lastInterruptTime = now
  return Skada.Data:RecordInterrupt(sourceName, targetName, abilityName, interruptedName, spellID, now)
end

function CastTracker:RecordRawInterrupt(sourceName, targetName, interruptedName, now)
  now = now or GetTime()
  local interruptIndex
  for interruptIndex = table_getn(self.pendingInterrupts), 1, -1 do
    local pending = self.pendingInterrupts[interruptIndex]
    if now <= pending.expires and pending.sourceName == sourceName and
       (not pending.targetName or pending.targetName == targetName) then
      self:RecordInterrupt(sourceName, targetName, pending.abilityName, interruptedName, pending.spellID, now)
      table_remove(self.pendingInterrupts, interruptIndex)
      return true
    end
  end
  return self:RecordInterrupt(sourceName, targetName, "Interrupt", interruptedName, nil, now)
end

function CastTracker:OnSpellSent(unit, target, castGUID, spellID, spellName)
  if unit ~= "player" then return end
  local now = GetTime()

  local targetName = target
  if targetName and targetName ~= "" and UnitExists and UnitExists(targetName) then
    targetName = UnitName(targetName) or targetName
  end
  local before
  if dispelCasts[spellID] then
    local targetUnit = self:FindTargetUnit(targetName)
    if targetUnit then
      local friendly = UnitIsFriend("player", targetUnit) and true or false
      before = self:SnapshotAuras(targetUnit, friendly, spellID == 19801)
    end
  end
  self.sentCasts[castGUID] = {
    targetName = targetName,
    spellID = spellID,
    spellName = spellName,
    before = before,
    time = now,
  }
end

function CastTracker:OnSpellSucceeded(unit, castGUID, spellID, spellName)
  local sourceName = unit and UnitName(unit)
  if not sourceName then return end
  local now = GetTime()
  self:RememberSpell(sourceName, spellName, spellID)

  local sent = castGUID and self.sentCasts[castGUID]
  local targetName = sent and sent.targetName
  if not targetName and UnitSpellTargetName then targetName = UnitSpellTargetName(unit) end
  if (not targetName or targetName == "") and UnitExists("target") then targetName = UnitName("target") end

  if dispelCasts[spellID] then
    self:NewDispelPending(sourceName, targetName, spellName, spellID, sent and sent.before, now)
  end

  if self:IsInterruptSpell(spellID, spellName) then
    table_insert(self.pendingInterrupts, {
      sourceName = sourceName,
      targetName = targetName,
      abilityName = spellName,
      spellID = spellID,
      expires = now + 1.0,
    })
  end

  if castGUID then self.sentCasts[castGUID] = nil end
end

function CastTracker:OnSpellInterrupted(unit, castGUID, interruptedSpellID, interruptedName)
  local targetName = unit and UnitName(unit)
  local now = GetTime()
  local interruptIndex
  for interruptIndex = table_getn(self.pendingInterrupts), 1, -1 do
    local pending = self.pendingInterrupts[interruptIndex]
    if now <= pending.expires and (not pending.targetName or pending.targetName == targetName) then
      self:RecordInterrupt(pending.sourceName, targetName, pending.abilityName, interruptedName, pending.spellID, now)
      table_remove(self.pendingInterrupts, interruptIndex)
      return
    end
  end
end

Skada:RegisterEvent("UNIT_SPELLCAST_SENT", function(eventName, unit, targetName, castGUID, spellID, spellName)
  local tracking = Skada.Tracking
  if tracking then tracking:OnSpellSent(unit, targetName, castGUID, spellID, spellName) end
end)
Skada:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(eventName, unit, castGUID, spellID, spellName)
  local tracking = Skada.Tracking
  if tracking then tracking:OnSpellSucceeded(unit, castGUID, spellID, spellName) end
end)
Skada:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(eventName, unit, castGUID, spellID, spellName)
  local tracking = Skada.Tracking
  if tracking then tracking:OnSpellInterrupted(unit, castGUID, spellID, spellName) end
end)
