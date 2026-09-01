local Skada = (_G or getfenv(0)).Skada

local DataSegments = {}
Skada.DataSegments = DataSegments

local Common = Skada.Common
local wipeTable = Common.Wipe
local DataAggregator = Skada.DataAggregator
local BossDetection = Skada.BossDetection

local max = math.max
local table_getn = table.getn
local table_insert = table.insert
local table_remove = table.remove

local BOSS_TARGET_SCAN_INTERVAL = 1

function DataSegments:StartSegment(now, targetName)
  now = now or GetTime()
  if self.active then return self.current end
  self.current = DataAggregator:NewSet(targetName or "Current", now, false)
  self.active = true
  self.noCombatSince = nil
  self.nextBossTargetScan = nil
  Skada:MarkDirty()
  return self.current
end

function DataSegments:EnsureSegment(now, targetName, mayStart)
  if not self.active then
    if not mayStart then return nil end
    return self:StartSegment(now, targetName)
  elseif targetName and self.current.name == "Current" then
    self.current.name = targetName
  end
  self.current.lastTime = now

  if not self.combatStateKnown or self.clientInCombat then
    self.noCombatSince = nil
  end
  return self.current
end

function DataSegments:GetSetDuration(segment)
  if not segment then return 0 end
  if segment.isTotal then
    local duration = segment.duration
    if self.active then duration = duration + max(0, GetTime() - self.current.startTime) end
    return duration
  end
  if self.active and segment == self.current then
    return max(0, GetTime() - segment.startTime)
  end
  return segment.duration or 0
end

function DataSegments:EachLiveSet(callback)
  callback(self.current)
  callback(self.total)
end

function DataSegments:IsGroupInCombat()
  local groupIndex, unitToken
  for groupIndex = 1, table_getn(self.groupTokens) do
    unitToken = self.groupTokens[groupIndex]
    if UnitExists(unitToken) and UnitAffectingCombat and UnitAffectingCombat(unitToken) then return true end
  end
  return false
end

function DataSegments:OnCombatEnter(now)
  self.clientInCombat = true
  self.combatStateKnown = true
  self.noCombatSince = nil
  self.nextGroupCheck = nil
  self.groupInCombat = nil
  self:StartSegment(now or GetTime())
  Skada:Publish("combatStateChanged", true)
end

function DataSegments:OnCombatLeave(now)
  self.clientInCombat = false
  self.combatStateKnown = true
  self.noCombatSince = now or GetTime()
  self.nextGroupCheck = nil
  self.groupInCombat = nil
  Skada:Publish("combatStateChanged", false)
end

function DataSegments:EndSegment(now)
  if not self.active then return end
  now = now or GetTime()
  local segment = self.current

  segment.duration = max(0, now - segment.startTime)
  segment.endTime = now
  self.active = false
  self.noCombatSince = nil
  self.nextBossTargetScan = nil

  if segment.hasData then
    self.total.duration = self.total.duration + segment.duration
    if segment.duration > 5 and (not Skada.db.profile.onlyBossFights or segment.gotboss) then
      table_insert(self.history, 1, segment)
      self:TrimHistory()

      Skada:Publish("segmentArchived", self, segment)
    end
  end
  Skada:MarkDirty()
end

function DataSegments:TrimHistory()
  while table_getn(self.history) > Skada.db.profile.maxSegments do
    table_remove(self.history)
  end
end

function DataSegments:Update(now)
  if not self.active then
    self.noCombatSince = nil
    self.nextBossTargetScan = nil
    return
  end

  if not self.current.gotboss and (not self.nextBossTargetScan or now >= self.nextBossTargetScan) then
    self.nextBossTargetScan = now + BOSS_TARGET_SCAN_INTERVAL
    local bossName, bossCreatureID = BossDetection:Find(self.groupTokens)
    if bossName then
      self.current.gotboss = true
      self.current.bossID = bossCreatureID
      self.current.name = bossName
    end
  end

  if self.clientInCombat then
    self.noCombatSince = nil
    return
  end

  if not self.nextGroupCheck or now >= self.nextGroupCheck then
    self.nextGroupCheck = now + 0.5
    self.groupInCombat = self:IsGroupInCombat()
  end
  if self.groupInCombat then
    self.noCombatSince = nil
    return
  end

  if not self.noCombatSince then
    self.noCombatSince = now
    return
  end

  local delay = self.combatStateKnown and 1.5 or 10
  if now - self.noCombatSince >= delay then self:EndSegment(now) end
end

function DataSegments:Reset()
  local now = GetTime()
  wipeTable(self.history)
  self.total = DataAggregator:NewSet("Overall", now, true)
  self.current = DataAggregator:NewSet("Current", now, false)
  self.active = false
  self.noCombatSince = nil
  self.nextBossTargetScan = nil
  Skada:Publish("dataReset")
  Skada:MarkDirty()
end

local function handleCombatEnter()
  local data = Skada.Data
  if data and data.identitiesByName then data:OnCombatEnter(GetTime()) end
end

local function handleCombatLeave()
  local data = Skada.Data
  if data and data.identitiesByName then data:OnCombatLeave(GetTime()) end
end

Skada:RegisterEvent("PLAYER_REGEN_DISABLED", handleCombatEnter)
Skada:RegisterEvent("PLAYER_REGEN_ENABLED", handleCombatLeave)
