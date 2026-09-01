local Skada = (_G or getfenv(0)).Skada

local ResetPolicy = {}
Skada.ResetPolicy = ResetPolicy

local tostring = tostring

local lastInInstance = nil
local lastGrouped = nil

local function getResetPolicy(key)
  local profile = Skada.db and Skada.db.profile
  return tostring(profile and profile[key] or "no")
end

local function isPlayerInInstance()
  if IsInInstance then return IsInInstance() and true or false end
  return false
end

local function isGrouped()
  local raidSize = GetNumRaidMembers and GetNumRaidMembers() or 0
  local partySize = GetNumPartyMembers and GetNumPartyMembers() or 0
  return raidSize > 0 or partySize > 0
end

function ResetPolicy:Apply(key, reason)
  local policy = getResetPolicy(key)
  if policy ~= "yes" and policy ~= "ask" then return end
  if Skada.Data.active then return end
  if policy == "yes" then
    Skada.Data:Reset()
    Skada:Print(reason .. " Data reset.")
    return
  end
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.SKADA_RESET_POLICY then
    StaticPopup_Show("SKADA_RESET_POLICY")
  else
    Skada.Data:Reset()
    Skada:Print(reason .. " Data reset.")
  end
end

local function handleZoneChanged()
  local currentlyInInstance = isPlayerInInstance()
  if lastInInstance == nil then
    lastInInstance = currentlyInInstance
    return
  end
  if currentlyInInstance and not lastInInstance then
    ResetPolicy:Apply("resetOnEnterInstance", "You entered an instance.")
  end
  lastInInstance = currentlyInInstance
end

local function handleGroupChanged()
  local currentlyGrouped = isGrouped()
  if lastGrouped == nil then
    lastGrouped = currentlyGrouped
    return
  end
  if currentlyGrouped and not lastGrouped then
    ResetPolicy:Apply("resetOnJoinGroup", "You joined a group.")
  elseif not currentlyGrouped and lastGrouped then
    ResetPolicy:Apply("resetOnLeaveGroup", "You left a group.")
  end
  lastGrouped = currentlyGrouped
end

Skada:RegisterInitializer(function()
  lastInInstance = isPlayerInInstance()
  lastGrouped = isGrouped()
end, "reset policies")

Skada:RegisterEvent("ZONE_CHANGED_NEW_AREA", handleZoneChanged)
Skada:RegisterEvent("PLAYER_ENTERING_WORLD", handleZoneChanged)
Skada:RegisterEvent("PARTY_MEMBERS_CHANGED", handleGroupChanged)
Skada:RegisterEvent("RAID_ROSTER_UPDATE", handleGroupChanged)
