local Skada = (_G or getfenv(0)).Skada

local DataIdentity = {}
Skada.DataIdentity = DataIdentity

local Common = Skada.Common
local wipeTable = Common.Wipe
local trim = Common.Trim

local string_match = Common.Match
local pairs = pairs

local table_getn = table.getn
local table_insert = table.insert

local commonUnitCandidates = { "target", "targettarget", "focus", "focustarget", "mouseover" }

-- Identities are keyed by name, and names are not unique: a hunter can name
-- a pet after a raid member, and a stranger's pet or a mob can share a
-- tracked name. A tracked identity belongs to the unit it was built from;
-- any other unit carrying the name must not take over its GUID, token or
-- owner. Group identities sit on a token, so "the same unit" is asked of the
-- client; summons have no token and fall back to their GUID. With nothing
-- to compare against, the unit is taken to be the same one, as before.
function DataIdentity:IsSameUnit(unit, guid, identity)
  if unit == identity.unit then return true end
  if identity.unit and UnitIsUnit and UnitExists(identity.unit) then
    return UnitIsUnit(unit, identity.unit) and true or false
  end
  if identity.guid and guid then return identity.guid == guid end
  return true
end

-- Whether a unit seen under a tracked name is someone else wearing it.
function DataIdentity:IsImpostor(unit, guid, identity)
  return identity and identity.interesting and not self:IsSameUnit(unit, guid, identity) or false
end

function DataIdentity:AddObservedUnit(unit, interesting, ownerName)
  if not unit or not UnitExists(unit) then return end
  local name = UnitName(unit)
  if not name then return end

  local guid = UnitGUID and UnitGUID(unit) or nil
  local _, class = UnitClass(unit)
  class = class or "OTHER"

  local identity = self.identitiesByName[name]
  if identity and self:IsImpostor(unit, guid, identity) then return end
  if not identity then
    identity = { name = name }
    self.identitiesByName[name] = identity
  end
  -- A tracked identity keeps its group token: "target" or a nameplate
  -- points elsewhere a moment later, and the impostor check above compares
  -- against this token.
  local keepsToken = identity.interesting and not interesting and identity.unit
  identity.guid = guid or identity.guid
  identity.class = class ~= "OTHER" and class or identity.class or "OTHER"
  if not keepsToken then identity.unit = unit end
  identity.owner = ownerName or identity.owner
  if interesting then
    local becameInteresting = not identity.interesting
    identity.interesting = true
    if becameInteresting then
      for cachedName, cachedIdentity in pairs(self.identitiesByName) do
        if cachedIdentity == false then
          self.identitiesByName[cachedName] = nil
        end
      end
    end
  end

  if not keepsToken then self.unitsByName[name] = unit end
  if guid then self.identitiesByGUID[guid] = identity end
  return identity
end

local function petTokenFor(unit)
  if unit == "player" then return "pet" end
  if string.sub(unit, 1, 4) == "raid" then return "raidpet" .. string.sub(unit, 5) end
  if string.sub(unit, 1, 5) == "party" then return "partypet" .. string.sub(unit, 6) end
  return unit .. "pet"
end

-- A group pet whose name another tracked unit already holds (a pet renamed
-- after a raid member, or two hunters' pets both called "Wolf") gets its own
-- identity under "Name (Owner)", the key ResolveSource already reads as an
-- owned pet. Its GUID points there, so GUID-keyed paths credit the owner;
-- the bare name stays with the unit that held it first.
function DataIdentity:AddGroupPet(petUnit, ownerName)
  local name = UnitName(petUnit)
  if not name then return end
  local guid = UnitGUID and UnitGUID(petUnit) or nil
  local holder = self.identitiesByName[name]
  if not self:IsImpostor(petUnit, guid, holder) then
    return self:AddObservedUnit(petUnit, true, ownerName)
  end

  local key = name .. " (" .. ownerName .. ")"
  local identity = self.identitiesByName[key]
  if not identity then
    identity = { name = key }
    self.identitiesByName[key] = identity
  end
  local _, class = UnitClass(petUnit)
  identity.class = class or identity.class or "OTHER"
  identity.guid = guid or identity.guid
  identity.unit = petUnit
  identity.owner = ownerName
  identity.interesting = true
  identity.collidesWith = name
  self.unitsByName[key] = petUnit
  if guid then self.identitiesByGUID[guid] = identity end
  return identity
end

function DataIdentity:AddGroupUnit(unit)
  if not unit or not UnitExists(unit) then return end
  local identity = self:AddObservedUnit(unit, true)
  if not identity then return end
  table_insert(self.groupTokens, unit)

  local petUnit = petTokenFor(unit)
  if UnitExists(petUnit) and self:AddGroupPet(petUnit, identity.name) then
    table_insert(self.groupTokens, petUnit)
  end
end

-- A summon the roster cannot see: a totem, a warlock's Infernal, a
-- Feral Spirit. Group pets sit on a pet token and come in through
-- AddGroupUnit; everything else has no token, so the Nampower ingest reports
-- it here once it has read the summoner off the unit's fields. The summon
-- becomes an owned identity, and ResolveSource merges its hits into the owner
-- like any pet. Same-named summons of two owners share one entry, so the
-- most recent owner wins; keyed by name, there is nowhere else to put it.
function DataIdentity:AddSummon(name, ownerName, guid)
  if not name or name == "" or not ownerName then return end
  local ownerIdentity = self.identitiesByName[ownerName]
  if not ownerIdentity or not ownerIdentity.interesting then return end

  local identity = self.identitiesByName[name]
  if not identity then
    identity = { name = name, class = "OTHER" }
    self.identitiesByName[name] = identity
  end
  identity.owner = ownerName
  identity.interesting = true
  identity.summon = true
  identity.guid = guid or identity.guid
  if guid then self.identitiesByGUID[guid] = identity end
  return identity
end

function DataIdentity:RebuildRoster()
  wipeTable(self.identitiesByName)
  wipeTable(self.identitiesByGUID)
  wipeTable(self.unitsByName)
  wipeTable(self.groupTokens)
  -- Bumped on every rebuild so callers that cache "this GUID has been
  -- checked for an owner" know their answer was wiped with the roster.
  self.rosterGeneration = (self.rosterGeneration or 0) + 1

  local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
  local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
  local tokenPrefix = raidCount > 0 and "raid" or "party"
  local memberCount = raidCount > 0 and raidCount or partyCount
  local unitIndex

  -- Players claim their names before any pet is read, so a pet renamed
  -- after a member is the one that yields, whatever the roster order.
  self:AddObservedUnit("player", true)
  for unitIndex = 1, memberCount do self:AddObservedUnit(tokenPrefix .. unitIndex, true) end

  self:AddGroupUnit("player")
  for unitIndex = 1, memberCount do self:AddGroupUnit(tokenPrefix .. unitIndex) end

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

  -- A target or mouseover wearing a tracked name is not that unit: reading
  -- its health would price a group member's heals off a stranger.
  local holder = self.identitiesByName[name]
  local candidateIndex
  for candidateIndex = 1, table_getn(commonUnitCandidates) do
    unit = commonUnitCandidates[candidateIndex]
    if UnitExists(unit) and UnitName(unit) == name
      and not self:IsImpostor(unit, UnitGUID and UnitGUID(unit), holder) then
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

-- Only a literal "You" stands for the player. A blank or missing name is a
-- unit the client could not see (a stranger's summon, an out-of-range
-- caster) and resolves to nothing rather than to the player. The blank
-- guard runs before the resolvers: if the YOU constant were ever unset, a
-- nil name must still not fall through to the player.
function DataIdentity:ResolveSource(name)
  name = trim(name)
  if not name or name == "" then return end
  if name == YOU or name == "You" then name = self.playerName end

  local identity = self.identitiesByName[name]
  local trackAll = Skada.db.profile.trackAll
  if identity == false then
    if not trackAll then return end
    identity = { name = name, class = "OTHER" }
    self.identitiesByName[name] = identity
  end
  if not identity then
    local owner = string_match(name, "%((.-)%)$")
    local ownerIdentity = owner and self.identitiesByName[owner]
    if ownerIdentity and ownerIdentity.interesting then
      identity = { name = name, owner = owner, class = "OTHER", interesting = true }
      self.identitiesByName[name] = identity
    elseif trackAll then
      identity = { name = name, class = "OTHER" }
      self.identitiesByName[name] = identity
    else
      self.identitiesByName[name] = false
      return
    end
  end

  if identity and identity.interesting then
    if identity.owner and Skada.db.profile.mergePets then
      local ownerIdentity = self.identitiesByName[identity.owner]
      return identity.owner, ownerIdentity or identity, name
    end
    return name, identity
  end

  if trackAll then
    return name, identity
  end
end

-- A summon is a source, never a target. A totem is hit by every mob near it
-- and dies by design when it fires, and a Voidwalker soaks hits for its
-- master; none of that belongs in damage taken, avoids or deaths. Group
-- pets on a pet token keep their own rows, as they always have.
function DataIdentity:IsSummon(name)
  local identity = name and self.identitiesByName[trim(name)]
  return identity and identity.summon and true or false
end

function DataIdentity:ResolveTarget(name)
  name = trim(name)
  if name == YOU or name == "You" then name = self.playerName end
  if not name or name == "" then return nil, nil, nil end
  local identity = self.identitiesByName[name]
  if identity and identity.interesting and not identity.summon then return name, identity, name end
  return nil, nil, name
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
