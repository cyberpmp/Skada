local Skada = (_G or getfenv(0)).Skada

local DataIdentity = {}
Skada.DataIdentity = DataIdentity

local Common = Skada.Common
local wipeTable = Common.Wipe
local trim = Common.Trim

local string_match = Common.Match

local table_getn = table.getn

local commonUnitCandidates = { "target", "targettarget", "focus", "focustarget", "mouseover" }

function DataIdentity:AddObservedUnit(unit, interesting, ownerName)
  if not unit or not UnitExists(unit) then return end
  local name = UnitName(unit)
  if not name then return end

  local guid = UnitGUID and UnitGUID(unit) or nil
  local _, class = UnitClass(unit)
  class = class or "OTHER"

  local identity = self.identitiesByName[name]
  if not identity then
    identity = { name = name }
    self.identitiesByName[name] = identity
  end
  identity.guid = guid or identity.guid
  identity.class = class ~= "OTHER" and class or identity.class or "OTHER"
  identity.unit = unit
  identity.owner = ownerName or identity.owner
  if interesting then identity.interesting = true end

  self.unitsByName[name] = unit
  if guid then self.identitiesByGUID[guid] = identity end
  return identity
end

function DataIdentity:AddGroupUnit(unit)
  if not unit or not UnitExists(unit) then return end
  local identity = self:AddObservedUnit(unit, true)
  if not identity then return end
  self.groupTokens[table_getn(self.groupTokens) + 1] = unit

  local petUnit
  if unit == "player" then
    petUnit = "pet"
  elseif string.sub(unit, 1, 4) == "raid" then
    petUnit = "raidpet" .. string.sub(unit, 5)
  elseif string.sub(unit, 1, 5) == "party" then
    petUnit = "partypet" .. string.sub(unit, 6)
  else
    petUnit = unit .. "pet"
  end
  if UnitExists(petUnit) then
    local petIdentity = self:AddObservedUnit(petUnit, true, identity.name)
    if petIdentity then
      self.groupTokens[table_getn(self.groupTokens) + 1] = petUnit
    end
  end
end

function DataIdentity:RebuildRoster()
  wipeTable(self.identitiesByName)
  wipeTable(self.identitiesByGUID)
  wipeTable(self.unitsByName)
  wipeTable(self.groupTokens)

  self:AddGroupUnit("player")

  local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
  local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
  local i
  if raidCount > 0 then
    for i = 1, raidCount do self:AddGroupUnit("raid" .. i) end
  else
    for i = 1, partyCount do self:AddGroupUnit("party" .. i) end
  end

  self.playerName = UnitName("player") or self.playerName or "Player"
  Skada:MarkDirty()
end

function DataIdentity:ObserveToken(unit)
  if unit and UnitExists(unit) then
    return self:AddObservedUnit(unit, false)
  end
end

function DataIdentity:FindUnitByName(name)
  name = trim(name)
  local unit = self.unitsByName[name]
  if unit and UnitExists(unit) and UnitName(unit) == name then return unit end

  local i
  for i = 1, table_getn(commonUnitCandidates) do
    unit = commonUnitCandidates[i]
    if UnitExists(unit) and UnitName(unit) == name then
      self:AddObservedUnit(unit, false)
      return unit
    end
  end
end

function DataIdentity:GetIdentityByGUID(guid)
  return guid and self.identitiesByGUID[guid] or nil
end

function DataIdentity:GetIdentityByName(name)
  return name and self.identitiesByName[trim(name)] or nil
end

function DataIdentity:ResolveSource(name)
  name = trim(name)
  if not name or name == "" or name == YOU or name == "You" then
    name = self.playerName
  end

  local identity = self.identitiesByName[name]
  if not identity then
    local owner = string_match(name, "%((.-)%)$")
    local ownerIdentity = owner and self.identitiesByName[owner]
    if ownerIdentity and ownerIdentity.interesting then
      identity = { name = name, owner = owner, class = "OTHER", interesting = true }
      self.identitiesByName[name] = identity
    end
  end

  if identity and identity.interesting then
    if identity.owner and Skada.db.profile.mergePets then
      local ownerIdentity = self.identitiesByName[identity.owner]
      return identity.owner, ownerIdentity or identity, name
    end
    return name, identity
  end

  if Skada.db.profile.trackAll then
    if not identity then
      identity = { name = name, class = "OTHER" }
      self.identitiesByName[name] = identity
    end
    return name, identity
  end
end

function DataIdentity:ResolveTarget(name)
  name = trim(name)
  if not name or name == "" or name == YOU or name == "You" then
    name = self.playerName
  end
  local identity = self.identitiesByName[name]
  if identity and identity.interesting then return name, identity end
end

local function handleRosterChanged()
  local data = Skada.Data
  if data and data.identitiesByName then data:RebuildRoster() end
end

local function handleWorldEntry()
  local data = Skada.Data
  if not data or not data.identitiesByName then return end
  data:RebuildRoster()
  if UnitAffectingCombat and UnitAffectingCombat("player") then
    data:OnCombatEnter(GetTime())
  end
end

Skada:RegisterEvent("PLAYER_ENTERING_WORLD", handleWorldEntry)
Skada:RegisterEvent("RAID_ROSTER_UPDATE", handleRosterChanged)
Skada:RegisterEvent("PARTY_MEMBERS_CHANGED", handleRosterChanged)
Skada:RegisterEvent("UNIT_PET", handleRosterChanged)
