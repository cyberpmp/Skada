local Skada = (_G or getfenv(0)).Skada

-- Threat API v1: the server-side threat protocol. These two strings are the
-- wire format the server matches byte for byte, so they keep their original
-- spelling; everything else refers to them by these names.
local THREAT_APIV1_QUERY = "TWT_UDTSv4"
local THREAT_APIV1_REPLY = "TWTv4="

local Threat = {
  requestPrefix = THREAT_APIV1_QUERY,
  responseMarker = THREAT_APIV1_REPLY,

  queryInterval = 0.5,
  burstInterval = 0.10,
  burstDuration = 0.60,
  missingGrace = 1.25,
  staleAfter = 2.5,
  estimateGrace = 2.0,
  serverHold = 0.75,
  requestLimit = 10,
  -- A server without the threat API never answers. Until the current group
  -- has heard one reply, this many unanswered queries in a row drop the
  -- provider to one re-probe per backoffInterval (and one per target switch)
  -- instead of flooding the group channel for the whole session.
  unansweredLimit = 8,
  backoffInterval = 15,
  -- A packet with more records than any real table (requestLimit rows plus
  -- a tank line) is rejected as forged.
  maxPacketRecords = 40,
  maxNameLength = 48,

  windowEnumerator = nil,
}
Skada.Threat = Threat

local Common = Skada.Common
local wipeTable = Common.Wipe

local pairs = pairs
local tonumber = tonumber
local table_getn = table.getn
local table_insert = table.insert
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

function Threat:IsSelfOrOwnPet(name)
  if not Skada.Data then return false end
  local playerName = Skada.Data:GetPlayerName()
  if not playerName then return false end
  if name == playerName then return true end
  local identity = Skada.Data:GetIdentityByName(name)
  if not identity then return false end
  return identity.owner == playerName
end

function Threat:SetWindowEnumerator(enumerator)
  self.windowEnumerator = enumerator
end

function Threat:GetChannel()
  return (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 and "RAID" or "PARTY"
end

function Threat:GetTargetName(requireCombat)
  local estimator = Skada.ThreatEstimate
  if not estimator or not estimator:IsLiveEnemyUnit("target") then return nil end
  if requireCombat and UnitAffectingCombat and not UnitAffectingCombat("player") then return nil end
  local name = UnitName and UnitName("target")
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
  wipeTable(self.rows)
  if clearSamples then wipeTable(self.rowsByName) end
  if hadRows then Skada:MarkDirty() end
end

function Threat:TargetChanged()
  local targetName = self:GetTargetName(false)
  local targetKey = self:GetTargetKey(targetName)
  local now = GetTime and GetTime() or 0
  if targetKey ~= self.targetKey then
    self.targetName = targetName
    self.targetKey = targetKey
    self:ResetTargetState(now)
    self.burstUntil = now + self.burstDuration
  elseif not targetName then
    self:ClearRows(true)
  end
  Skada:MarkDirty()

  if self:NeedsUpdates(now) then self:Update(now) end
end

-- Everything tied to the previous target or the previous server exchange.
-- now starts the wait for a server reply on the new target.
function Threat:ResetTargetState(now)
  self.requestTarget = nil
  self.nextQuery = 0
  self.lastResponse = nil
  self.lastServerResponse = nil
  self.serverWaitSince = now
  self.usingEstimate = false
  self:ClearRows(true)
end

function Threat:GroupChanged()
  self:ResetTargetState(GetTime and GetTime() or 0)
  -- A new roster may have a different threat server than the old one, or
  -- none at all: the wait-for-server-reply hold must be relearned, not kept
  -- for the rest of the session on the strength of the old group's packets.
  self.receivedPackets = 0
  self.unansweredQueries = 0
  local estimator = Skada.ThreatEstimate
  if estimator then
    estimator:PruneActors(function(actorName)
      if self:IsSelfOrOwnPet(actorName) then return true end
      local identity = Skada.Data and Skada.Data:GetIdentityByName(actorName)
      return identity ~= nil and identity ~= false
    end)
  end
  self:TargetChanged()
end

function Threat:NeedsUpdates(now, wanted)
  if wanted == nil then
    local windows = self.windowEnumerator and self.windowEnumerator()
    if not windows then return false end
    local windowIndex, window
    for windowIndex = 1, table_getn(windows) do
      window = windows[windowIndex]
      if not window.broken and window.db.visible and window.db.mode == "threat" and window.view == "mode" then
        wanted = true
        break
      end
    end
  end
  if not wanted then return false end

  now = now or GetTime()
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

  local ungrouped = not self:IsGrouped()
  local name, row, source, entryIndex
  for name, row in pairs(self.rowsByName) do row.seen = false end
  wipeTable(self.rows)

  for entryIndex = 1, count do
    source = entries[entryIndex]
    name = source.name
    if not ungrouped or self:IsSelfOrOwnPet(name) then
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
      table_insert(self.rows, row)
    end
  end

  for name, row in pairs(self.rowsByName) do
    if not row.seen then self.rowsByName[name] = nil end
  end
  self.lastResponse = now
  self.usingEstimate = true
  Skada:MarkDirty()
  return true
end

function Threat:Update(now)
  if not self:NeedsUpdates(now) then return end

  local targetName = self:GetTargetName(true)

  if not targetName and self.burstUntil and UnitAffectingCombat and UnitAffectingCombat("player") then
    targetName = self:GetTargetName(false)
  end
  local targetKey = self:GetTargetKey(targetName)
  if targetKey ~= self.targetKey then
    local changedAt = GetTime and GetTime() or now
    self.targetName = targetName
    self.targetKey = targetKey
    self:ResetTargetState(changedAt)
    self.burstUntil = changedAt + self.burstDuration
  end

  if not targetName then
    self.requestTarget = nil
    self:ClearRows(false)
    return
  end

  -- The local estimate paints immediately and a live server reply replaces
  -- it; the estimate only steps back in once server data has gone stale.
  -- Grouped players who have already heard from a threat server get a short
  -- hold after a switch so the reply paints first instead of an estimate
  -- that the reply would reshuffle a moment later. Solo players, and groups
  -- without a server, never wait for data that cannot arrive.
  local serverFresh = self.lastServerResponse and now - self.lastServerResponse <= self.estimateGrace
  local holdForServer = self:IsGrouped() and (self.receivedPackets or 0) > 0
  local waitedLongEnough = now - (self.serverWaitSince or now) >= self.serverHold
  if not serverFresh and (not holdForServer or waitedLongEnough) then
    self:ApplyEstimate(now, targetName, targetKey)
  end

  if self.lastResponse and now - self.lastResponse > self.staleAfter then
    self.lastResponse = nil
    self:ClearRows(true)
  end

  if not SendAddonMessage or not self:IsGrouped() or now < (self.nextQuery or 0) then return end
  local interval = (self.burstUntil and now < self.burstUntil) and self.burstInterval or self.queryInterval
  if (self.receivedPackets or 0) == 0 and (self.unansweredQueries or 0) >= self.unansweredLimit then
    interval = self.backoffInterval
  end
  self.nextQuery = now + interval
  self.requestTarget = targetKey
  self.unansweredQueries = (self.unansweredQueries or 0) + 1
  pcall(SendAddonMessage, self.requestPrefix, "limit=" .. self:GetQueryLimit(), self:GetChannel())
end

-- Addon messages from players carry the sender's name, set by the server,
-- so a group member cannot pose as the threat server: a reply "from" anyone
-- in the roster other than the player is a relay or a forgery. Only roster
-- members can post to PARTY and RAID, so checking the roster tokens covers
-- every player sender there. The roster is read off the tokens, not the
-- identity table, where a pet named after a member can mask that member.
-- The guild and battleground channels reach players outside the group and
-- never carry a reply to a party or raid query.
function Threat:IsTrustedSender(channel, sender)
  if channel == "GUILD" or channel == "BATTLEGROUND" then return false end
  if type(sender) ~= "string" or sender == "" then return true end
  if UnitName and sender == UnitName("player") then return true end
  local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
  local memberCount = raidCount > 0 and raidCount or (GetNumPartyMembers and GetNumPartyMembers() or 0)
  local tokenPrefix = raidCount > 0 and "raid" or "party"
  local memberIndex
  for memberIndex = 1, memberCount do
    if UnitName(tokenPrefix .. memberIndex) == sender then return false end
  end
  return true
end

-- Row names are drawn on bars and may be reported to chat: anything that is
-- not a plausible unit name (an escape sequence, a control character, an
-- overlong string) marks the whole packet as forged.
function Threat:IsValidRowName(name)
  if string.len(name) > self.maxNameLength then return false end
  return not string_find(name, "[\1-\31|]")
end

local function isFiniteNumber(value)
  return value ~= nil and value - value == 0
end

function Threat:RejectPacket(channel, sender, reason)
  self.rejectedPackets = (self.rejectedPackets or 0) + 1
  if self.rejectionReported then return end
  self.rejectionReported = true
  Skada:Print("Ignored a threat packet (" .. reason .. ") from " ..
    tostring(sender) .. " on " .. tostring(channel) .. ". Further ones are dropped silently.")
end

function Threat:OnAddonMessage(eventName, prefix, message, channel, sender)

  local payload = message
  local markerAt = type(payload) == "string" and string_find(payload, self.responseMarker, 1, true)
  if not markerAt and type(prefix) == "string" then
    payload = prefix
    markerAt = string_find(payload, self.responseMarker, 1, true)
  end
  if not markerAt then return end
  if not self:IsTrustedSender(channel, sender) then
    self:RejectPacket(channel, sender, "sent by a player")
    return
  end

  local targetName = self:GetTargetName(true)
  local targetKey = self:GetTargetKey(targetName)
  if not targetName or targetKey ~= self.targetKey or targetKey ~= self.requestTarget then return end

  payload = string_sub(payload, markerAt + string.len(self.responseMarker))
  local tankPacketAt = string_find(payload, "#", 1, true)
  if tankPacketAt then payload = string_sub(payload, 1, tankPacketAt - 1) end

  -- Validate the whole packet before touching any row, so a malformed one
  -- leaves the previous table in place instead of half-applying.
  local record, name, row, tankFlag, threatValue, percentValue, meleeFlag
  local recordCount = 0
  for record in string_gmatch(payload, "([^;]+)") do
    recordCount = recordCount + 1
    if recordCount > self.maxPacketRecords then
      self:RejectPacket(channel, sender, "too many rows")
      return
    end
    name, tankFlag, threatValue, percentValue = string_match(record, "^([^:]+):([^:]*):([^:]*):([^:]*)")
    if name and not self:IsValidRowName(name) then
      self:RejectPacket(channel, sender, "malformed name")
      return
    end
    threatValue, percentValue = tonumber(threatValue), tonumber(percentValue)
    if (threatValue and not isFiniteNumber(threatValue)) or (percentValue and not isFiniteNumber(percentValue)) then
      self:RejectPacket(channel, sender, "malformed value")
      return
    end
  end

  local now = GetTime()
  local ungrouped = not self:IsGrouped()

  for name, row in pairs(self.rowsByName) do row.seen = false end
  wipeTable(self.rows)

  local identity
  for record in string_gmatch(payload, "([^;]+)") do
    name, tankFlag, threatValue, percentValue, meleeFlag =
      string_match(record, "^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*)")
    threatValue = tonumber(threatValue)
    percentValue = tonumber(percentValue)
    if name and threatValue and percentValue
      and (not ungrouped or self:IsSelfOrOwnPet(name)) then
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
        table_insert(self.rows, row)
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
      table_insert(self.rows, row)
    end
  end

  table_sort(self.rows, sortRows)
  self.lastResponse = now
  self.lastServerResponse = now
  self.usingEstimate = false
  self.burstUntil = nil
  self.receivedPackets = (self.receivedPackets or 0) + 1
  self.unansweredQueries = 0
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
  self:ResetTargetState(GetTime and GetTime() or 0)
  self.burstUntil = nil
  self.receivedPackets = 0
  self.unansweredQueries = 0
  self.rejectedPackets = 0
  self.estimateRows = {}
end

Skada:RegisterEvent("CHAT_MSG_ADDON", function(eventName, prefix, message, channel, sender)
  Threat:OnAddonMessage(eventName, prefix, message, channel, sender)
end)
Skada:RegisterEvent("PLAYER_TARGET_CHANGED", function() Threat:TargetChanged() end)
Skada:RegisterEvent("PLAYER_REGEN_DISABLED", function()
  Threat:ResetTargetState(GetTime())
  Threat:TargetChanged()
end)
Skada:RegisterEvent("PLAYER_REGEN_ENABLED", function()
  Threat:ResetTargetState(GetTime())
  Skada:MarkDirty()
end)
Skada:RegisterEvent("PARTY_MEMBERS_CHANGED", function() Threat:GroupChanged() end)
Skada:RegisterEvent("RAID_ROSTER_UPDATE", function() Threat:GroupChanged() end)

Skada:RegisterInitializer(function() Threat:Initialize() end, "live threat")

Skada:RegisterTicker("threat", 0.20, function(now) Threat:Update(now) end)
