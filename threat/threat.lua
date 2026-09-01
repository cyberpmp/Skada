local Skada = (_G or getfenv(0)).Skada

local Threat = {
  requestPrefix = "TWT_UDTSv4",
  responseMarker = "TWTv4=",

  queryInterval = 0.5,
  burstInterval = 0.10,
  burstDuration = 0.60,
  missingGrace = 1.25,
  staleAfter = 2.5,
  estimateGrace = 2.0,
  requestLimit = 10,

  windowEnumerator = nil,
}
Skada.Threat = Threat

local Common = Skada.Common
local wipeTable = Common.Wipe

local pairs = pairs
local tonumber = tonumber
local table_getn = table.getn
local table_sort = table.sort
local string_find = string.find

local string_gmatch = string.gmatch
local string_match = Common.Match
local string_sub = string.sub

local function sortRows(left, right)
  if left.threat == right.threat then return left.name < right.name end
  return left.threat > right.threat
end

function Threat:IsGrouped()
  local raidSize = GetNumRaidMembers and GetNumRaidMembers() or 0
  local partySize = GetNumPartyMembers and GetNumPartyMembers() or 0
  return raidSize > 0 or partySize > 0
end

function Threat:SetWindowEnumerator(fn)
  self.windowEnumerator = fn
end

function Threat:GetChannel()
  return (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 and "RAID" or "PARTY"
end

function Threat:GetTargetName(requireCombat)
  if not UnitExists or not UnitExists("target") then return nil end
  if UnitIsDead and UnitIsDead("target") then return nil end
  if UnitIsPlayer and UnitIsPlayer("target") then return nil end
  if UnitCanAttack and not UnitCanAttack("player", "target") then return nil end
  if requireCombat and UnitAffectingCombat and not UnitAffectingCombat("player") then return nil end
  local name = UnitName("target")
  if not name or name == "" then return nil end
  return name
end

function Threat:GetTargetKey(targetName)
  if not targetName then return nil end
  local guid = UnitGUID and UnitGUID("target")
  return guid or targetName
end

function Threat:ClearRows(clearSamples)
  local hadRows = table_getn(self.rows) > 0
  local i
  for i = 1, table_getn(self.rows) do self.rows[i] = nil end
  if clearSamples then wipeTable(self.rowsByName) end
  if hadRows then Skada:MarkDirty() end
end

function Threat:TargetChanged()
  local targetName = self:GetTargetName(false)
  local targetKey = self:GetTargetKey(targetName)
  if targetKey ~= self.targetKey then
    local now = GetTime and GetTime() or 0
    self.targetName = targetName
    self.targetKey = targetKey
    self.requestTarget = nil
    self.nextQuery = 0
    self.lastResponse = nil
    self.lastServerResponse = nil
    self.serverWaitSince = now
    self.usingEstimate = false
    self.burstUntil = now + self.burstDuration
    self:ClearRows(true)
  elseif not targetName then
    self:ClearRows(true)
  end
  Skada:MarkDirty()

  if self:NeedsUpdates() then self:Update(GetTime()) end
end

function Threat:GroupChanged()
  self.requestTarget = nil
  self.nextQuery = 0
  self.lastResponse = nil
  self.lastServerResponse = nil
  self.serverWaitSince = GetTime()
  self.usingEstimate = false
  self:ClearRows(true)
  self:TargetChanged()
end

function Threat:NeedsUpdates()
  local windows = self.windowEnumerator and self.windowEnumerator()
  if not windows then return false end
  local i, window, wanted
  for i = 1, table_getn(windows) do
    window = windows[i]
    if window.db.visible and window.db.mode == "threat" and window.view == "mode" then
      wanted = true
      break
    end
  end
  if not wanted then return false end

  local now = GetTime()
  if self.lastResponse and now - self.lastResponse <= self.staleAfter then return true end
  if self.burstUntil and now < self.burstUntil then return true end
  return self:GetTargetName(true) ~= nil
end

function Threat:GetQueryLimit() return self.requestLimit end

function Threat:ApplyEstimate(now, targetName, targetKey)
  local estimator = Skada.ThreatEstimate
  if not estimator then return false end
  local entries, count = estimator:Build(targetName, targetKey, self.estimateRows)
  if count == 0 then return false end

  local previousCount = table_getn(self.rows)
  local name, row, source, i
  for name, row in pairs(self.rowsByName) do row.seen = false end

  for i = 1, count do
    source = entries[i]
    name = source.name
    row = self.rowsByName[name]
    if not row then
      row = { name = name }
      self.rowsByName[name] = row
    end
    if not row.estimated then
      row.tps = nil
      row.lastSeen = nil
    end
    if row.threat ~= nil and row.lastSeen and now > row.lastSeen then
      local delta = source.threat - row.threat
      if delta < 0 then
        row.tps = 0
      else
        local instantaneous = delta / (now - row.lastSeen)
        row.tps = row.tps and (row.tps * 0.65 + instantaneous * 0.35) or instantaneous
      end
    end
    row.threat = source.threat
    row.percent = source.percent
    row.tank = source.tank
    row.melee = source.melee
    row.class = source.class or "OTHER"
    row.estimated = true
    row.lastSeen = now
    row.seen = true
    self.rows[i] = row
  end

  for name, row in pairs(self.rowsByName) do
    if not row.seen then self.rowsByName[name] = nil end
  end
  for i = count + 1, previousCount do self.rows[i] = nil end
  table_sort(self.rows, sortRows)
  self.lastResponse = now
  self.usingEstimate = true
  Skada:MarkDirty()
  return true
end

function Threat:Update(now)
  if not self:NeedsUpdates() then return end

  local targetName = self:GetTargetName(true)

  if not targetName and self.burstUntil and UnitAffectingCombat and UnitAffectingCombat("player") then
    targetName = self:GetTargetName(false)
  end
  local targetKey = self:GetTargetKey(targetName)
  if targetKey ~= self.targetKey then
    local changedAt = GetTime and GetTime() or now
    self.targetName = targetName
    self.targetKey = targetKey
    self.requestTarget = nil
    self.nextQuery = 0
    self.lastResponse = nil
    self.lastServerResponse = nil
    self.serverWaitSince = changedAt
    self.usingEstimate = false
    self.burstUntil = changedAt + self.burstDuration
    self:ClearRows(true)
  end

  if not targetName then
    self.requestTarget = nil
    self:ClearRows(false)
    return
  end

  local serverFresh = self.lastServerResponse and now - self.lastServerResponse <= self.estimateGrace
  local waitedLongEnough = now - (self.serverWaitSince or now) >= self.estimateGrace
  if not serverFresh and waitedLongEnough then
    self:ApplyEstimate(now, targetName, targetKey)
  end

  if self.lastResponse and now - self.lastResponse > self.staleAfter then
    self.lastResponse = nil
    self:ClearRows(true)
  end

  if not SendAddonMessage or now < (self.nextQuery or 0) then return end
  local interval = (self.burstUntil and now < self.burstUntil) and self.burstInterval or self.queryInterval
  self.nextQuery = now + interval
  self.requestTarget = targetKey
  pcall(SendAddonMessage, self.requestPrefix, "limit=" .. self:GetQueryLimit(), self:GetChannel())
end

function Threat:OnAddonMessage(eventName, prefix, message)

  local payload = message
  local markerAt = type(payload) == "string" and string_find(payload, self.responseMarker, 1, true)
  if not markerAt and type(prefix) == "string" then
    payload = prefix
    markerAt = string_find(payload, self.responseMarker, 1, true)
  end
  if not markerAt then return end

  local targetName = self:GetTargetName(true)
  local targetKey = self:GetTargetKey(targetName)
  if not targetName or targetKey ~= self.targetKey or targetKey ~= self.requestTarget then return end

  payload = string_sub(payload, markerAt + string.len(self.responseMarker))
  local tankPacketAt = string_find(payload, "#", 1, true)
  if tankPacketAt then payload = string_sub(payload, 1, tankPacketAt - 1) end

  local previousCount = table_getn(self.rows)
  local now = GetTime()

  local name, row
  for name, row in pairs(self.rowsByName) do row.seen = false end

  local count = 0
  local record, tankFlag, threatValue, percentValue, meleeFlag
  local identity
  for record in string_gmatch(payload, "([^;]+)") do
    name, tankFlag, threatValue, percentValue, meleeFlag =
      string_match(record, "^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*)")
    threatValue = tonumber(threatValue)
    percentValue = tonumber(percentValue)
    if name and threatValue and percentValue then
      row = self.rowsByName[name]
      if not row then
        row = { name = name }
        self.rowsByName[name] = row
      end
      if row.estimated then
        row.tps = nil
        row.lastSeen = nil
      end
      if row.threat ~= nil and row.lastSeen and now > row.lastSeen then
        local delta = threatValue - row.threat
        if delta < 0 then
          row.tps = 0
        else
          local instantaneous = delta / (now - row.lastSeen)
          row.tps = row.tps and (row.tps * 0.65 + instantaneous * 0.35) or instantaneous
        end
      end
      row.threat = threatValue
      row.percent = percentValue
      row.tank = tankFlag == "1"
      row.melee = meleeFlag == "1"
      row.lastSeen = now
      row.estimated = false
      identity = Skada.Data and Skada.Data:GetIdentityByName(name)
      row.class = identity and identity.class or "OTHER"
      if not row.seen then
        row.seen = true
        count = count + 1
        self.rows[count] = row
      end
    end
  end

  for name, row in pairs(self.rowsByName) do
    if not row.seen and (row.estimated or not (row.lastSeen and now - row.lastSeen <= self.missingGrace)) then
      self.rowsByName[name] = nil
    end
  end
  for name, row in pairs(self.rowsByName) do
    if not row.seen then
      count = count + 1
      self.rows[count] = row
    end
  end
  local i
  for i = count + 1, previousCount do self.rows[i] = nil end

  table_sort(self.rows, sortRows)
  self.lastResponse = now
  self.lastServerResponse = now
  self.usingEstimate = false
  self.burstUntil = nil
  self.receivedPackets = (self.receivedPackets or 0) + 1
  Skada:MarkDirty()
end

function Threat:GetTitle()
  local targetName = self:GetTargetName(true)
  if not targetName then return "Threat: No active target" end
  return "Threat: " .. targetName .. (self.usingEstimate and " (estimated)" or "")
end

function Threat:GetSummaryText()
  if not self:GetTargetName(true) then return "No active target" end
  if table_getn(self.rows) == 0 then return "Waiting" end
  return self.usingEstimate and "Estimated" or "Live"
end

function Threat:Initialize()
  self.rows = {}
  self.rowsByName = {}
  self.targetName = self:GetTargetName(false)
  self.targetKey = self:GetTargetKey(self.targetName)
  self.requestTarget = nil
  self.nextQuery = 0
  self.lastResponse = nil
  self.lastServerResponse = nil
  self.serverWaitSince = GetTime()
  self.burstUntil = nil
  self.receivedPackets = 0
  self.usingEstimate = false
  self.estimateRows = {}
end

Skada:RegisterEvent("CHAT_MSG_ADDON", function(eventName, prefix, message)
  Threat:OnAddonMessage(eventName, prefix, message)
end)
Skada:RegisterEvent("PLAYER_TARGET_CHANGED", function() Threat:TargetChanged() end)
Skada:RegisterEvent("PLAYER_REGEN_DISABLED", function()
  Threat.lastResponse = nil
  Threat.lastServerResponse = nil
  Threat.serverWaitSince = GetTime()
  Threat.usingEstimate = false
  Threat:TargetChanged()
end)
Skada:RegisterEvent("PLAYER_REGEN_ENABLED", function()
  Threat.requestTarget = nil
  Threat.lastResponse = nil
  Threat.lastServerResponse = nil
  Threat.serverWaitSince = nil
  Threat.usingEstimate = false
  Threat:ClearRows(true)
  Skada:MarkDirty()
end)
Skada:RegisterEvent("PARTY_MEMBERS_CHANGED", function() Threat:GroupChanged() end)
Skada:RegisterEvent("RAID_ROSTER_UPDATE", function() Threat:GroupChanged() end)

Skada:RegisterInitializer(function() Threat:Initialize() end, "OctoWoW live threat")

Skada:RegisterTicker("threat", 0.20, function(now) Threat:Update(now) end)
