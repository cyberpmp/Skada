local Skada = (_G or getfenv(0)).Skada

local Tracking = {}
Skada.Tracking = Tracking

local SpellRegistry = Skada.SpellRegistry
local CastTracker = Skada.CastTracker
local AuraScanner = Skada.AuraScanner
local DamageWitness = Skada.DamageWitness
local GroupObserver = Skada.GroupObserver

local table_getn = table.getn
local table_remove = table.remove
local pairs = pairs

Tracking.RememberSpell = SpellRegistry.RememberSpell
Tracking.GetSpellID = SpellRegistry.GetSpellID
Tracking.GetSpellIcon = SpellRegistry.GetSpellIcon
Tracking.IsInterruptSpell = SpellRegistry.IsInterruptSpell

Tracking.NewDispelPending = CastTracker.NewDispelPending
Tracking.RecordDispel = CastTracker.RecordDispel
Tracking.ResolveDispelSnapshot = CastTracker.ResolveDispelSnapshot
Tracking.RecordRawDispel = CastTracker.RecordRawDispel
Tracking.RecordInterrupt = CastTracker.RecordInterrupt
Tracking.RecordRawInterrupt = CastTracker.RecordRawInterrupt
Tracking.OnSpellSent = CastTracker.OnSpellSent
Tracking.OnSpellSucceeded = CastTracker.OnSpellSucceeded
Tracking.OnSpellInterrupted = CastTracker.OnSpellInterrupted

Tracking.SnapshotAuras = AuraScanner.SnapshotAuras
Tracking.GetAuraSource = AuraScanner.GetAuraSource
Tracking.ScanCC = AuraScanner.ScanCC
Tracking.ScanAuraKind = AuraScanner.ScanAuraKind
Tracking.ScanAll = AuraScanner.ScanAll
Tracking.ClearCCForToken = AuraScanner.ClearCCForToken
Tracking.OnUnitAura = AuraScanner.OnUnitAura

Tracking.FindTargetUnit = DamageWitness.FindTargetUnit
Tracking.GetLastDamageInfo = DamageWitness.GetLastDamageInfo
Tracking.NoteDamage = DamageWitness.NoteDamage

Tracking.ObserveGroup = GroupObserver.ObserveGroup

function Tracking:Initialize()
  self.sentCasts = {}
  self.pendingDispels = {}
  self.pendingInterrupts = {}
  self.spellIDs = {}
  self.interruptCache = {}
  self.iconCache = {}
  self.ccByTarget = {}
  self.debuffsByTarget = {}
  self.buffsByTarget = {}
  self.auraCacheSeen = {}
  self.guidByToken = {}
  self.lastDamageByTarget = {}
  self.seenAuras = {}
  self.seenAuraKind = {}
  self.lastInterruptKey = nil
  self.lastInterruptTime = 0
  self.lastDispelKey = nil
  self.lastDispelTime = 0
  self.auraAPI = C_UnitAuras and C_UnitAuras.UnitAura and C_UnitAuras.GetUnitAuraBySpellID
  self:ObserveGroup(false)
end

function Tracking:Update(now)

  if now - (self.lastPrune or 0) > 5 then
    self.lastPrune = now
    local guid, entry
    for guid, entry in pairs(self.lastDamageByTarget) do
      if now - entry.time > 30 then self.lastDamageByTarget[guid] = nil end
    end

    local staleBefore = now - 120
    local seen
    for guid, seen in pairs(self.auraCacheSeen) do
      if seen < staleBefore then
        self.ccByTarget[guid] = nil
        self.debuffsByTarget[guid] = nil
        self.buffsByTarget[guid] = nil
        self.auraCacheSeen[guid] = nil
      end
    end
  end

  local i
  for i = table_getn(self.pendingDispels), 1, -1 do
    local pending = self.pendingDispels[i]
    if now >= pending.ready and self:ResolveDispelSnapshot(pending, now) then
      table_remove(self.pendingDispels, i)
    elseif now > pending.expires then
      table_remove(self.pendingDispels, i)
    end
  end

  for i = table_getn(self.pendingInterrupts), 1, -1 do
    if now > self.pendingInterrupts[i].expires then table_remove(self.pendingInterrupts, i) end
  end

  local castGUID, cast
  for castGUID, cast in pairs(self.sentCasts) do
    if now - cast.time > 5 then self.sentCasts[castGUID] = nil end
  end
end

Skada:RegisterInitializer(function() Tracking:Initialize() end, "cast and aura tracking")

Skada:RegisterTicker("tracking", 0.20, function(now) Tracking:Update(now) end)
