-- Nampower combat ingest.
--
-- Nampower republishes the server's combat packets as Lua events carrying real
-- GUIDs, spell IDs and unmitigated amounts. When those events are available this
-- module becomes the authoritative source for damage, healing, power gains,
-- avoidance, dispels and deaths, and the localized chat-text routes in
-- combat.parser.lua are suppressed for exactly those facts so nothing is counted
-- twice. Facts Nampower does not publish (interrupts, aura uptime, crowd
-- control) stay on the parser regardless.
--
-- Resolution of a GUID to a display name relies on the client's SuperWoW-style
-- UnitName(guid) extension. The module probes for it at login and refuses to
-- activate without it, because every Skada aggregate is keyed by actor name.

local Skada = (_G or getfenv(0)).Skada

local Nampower = {
  available = false,
  active = false,
  version = nil,
  reason = "not probed",
  eventCount = 0,
  unresolvedGUIDCount = 0,
}
Skada.Nampower = Nampower

local type = type
local tonumber = tonumber
local pairs = pairs
local math_floor = math.floor
-- Lua 5.0 on the client exposes math.mod; math.fmod is the name everywhere
-- newer, including the test runtime.
local math_mod = math.fmod or math.mod
local string_find = string.find
local string_sub = string.sub
local string_len = string.len

local EMPTY_GUID = "0x0000000000000000"

-- Vanilla Lua 5.0 has no bitwise operators and the bit library is not
-- guaranteed on this client, so flags are tested arithmetically.
local function hasFlag(value, flag)
  value = tonumber(value)
  if not value or value < flag then return false end
  return math_mod(math_floor(value / flag), 2) == 1
end

local HITINFO_LEFTSWING = 4
local HITINFO_MISS = 16
local HITINFO_CRITICALHIT = 128
local HITINFO_GLANCING = 16384
local HITINFO_CRUSHING = 32768

local SPELL_HITINFO_CRITICAL = 2

local VICTIMSTATE_AVOIDANCE = {
  [2] = "Dodge",
  [3] = "Parry",
  [6] = "Evade",
  [7] = "Immune",
  [8] = "Deflect",
}

local SPELL_MISS_NAMES = {
  [1] = "Miss",
  [2] = "Resist",
  [3] = "Dodge",
  [4] = "Parry",
  [5] = "Block",
  [6] = "Evade",
  [7] = "Immune",
  [8] = "Immune",
  [9] = "Deflect",
  [10] = "Absorb",
  [11] = "Reflect",
}

local SCHOOL_NAMES = {
  [0] = "Physical",
  [1] = "Holy",
  [2] = "Fire",
  [3] = "Nature",
  [4] = "Frost",
  [5] = "Shadow",
  [6] = "Arcane",
}

local ENVIRONMENT_NAMES = {
  [0] = "Fatigue",
  [1] = "Drowning",
  [2] = "Falling",
  [3] = "Lava",
  [4] = "Slime",
  [5] = "Fire",
  [6] = "Falling",
}

local POWER_NAMES = {
  [0] = "Mana",
  [1] = "Rage",
  [2] = "Focus",
  [3] = "Energy",
  [4] = "Happiness",
}

-- Identity ------------------------------------------------------------------

-- GUID to name, warmed by every combat event. Bounded so a long session in a
-- crowded zone cannot grow it without limit; a wipe only costs the next lookup
-- for each unit still in the fight.
local nameByGUID = {}
local nameCacheSize = 0
local NAME_CACHE_LIMIT = 2000

local function rememberName(guid, name)
  if nameByGUID[guid] then
    nameByGUID[guid] = name
    return name
  end
  if nameCacheSize >= NAME_CACHE_LIMIT then
    nameByGUID = {}
    nameCacheSize = 0
  end
  nameByGUID[guid] = name
  nameCacheSize = nameCacheSize + 1
  return name
end

local function forgetName(guid)
  if nameByGUID[guid] == nil then return end
  nameByGUID[guid] = nil
  nameCacheSize = nameCacheSize - 1
end

local function isRealGUID(guid)
  return type(guid) == "string" and guid ~= "" and guid ~= EMPTY_GUID
end

function Nampower:ResolveName(guid)
  if not isRealGUID(guid) then return nil end

  local identity = Skada.Data:GetIdentityByGUID(guid)
  if identity and identity.name then
    return rememberName(guid, identity.name)
  end

  local name = UnitName(guid)
  if type(name) == "string" and name ~= "" and name ~= "Unknown" then
    return rememberName(guid, name)
  end

  local remembered = nameByGUID[guid]
  if not remembered then self.unresolvedGUIDCount = self.unresolvedGUIDCount + 1 end
  return remembered
end

local resolveName

-- Spell names ---------------------------------------------------------------

local spellNameByID = {}

function Nampower:ResolveSpellName(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID == 0 then return nil end

  local cached = spellNameByID[spellID]
  if cached then return cached end

  local name
  if GetSpellNameAndRankForId then name = GetSpellNameAndRankForId(spellID) end
  if (not name or name == "") and SpellInfo then name = SpellInfo(spellID) end
  if (not name or name == "") and GetSpellRecField then name = GetSpellRecField(spellID, "name") end
  if not name or name == "" then name = "Spell #" .. spellID end

  spellNameByID[spellID] = name
  return name
end

local resolveSpellName

-- Mitigation ----------------------------------------------------------------

-- Skada's damage records carry a single mitigation observation per hit, matching
-- what a chat line can express. Nampower reports absorb, block and resist
-- together, so the largest non-zero component wins and the rest are dropped.
local function pickMitigation(absorbed, blocked, resisted)
  absorbed = tonumber(absorbed) or 0
  blocked = tonumber(blocked) or 0
  resisted = tonumber(resisted) or 0

  local bestType, bestAmount
  if absorbed > 0 then bestType, bestAmount = "absorbed", absorbed end
  if blocked > (bestAmount or 0) then bestType, bestAmount = "blocked", blocked end
  if resisted > (bestAmount or 0) then bestType, bestAmount = "resisted", resisted end
  return bestType, bestAmount
end

-- "absorb,block,resist" as emitted by SPELL_DAMAGE_EVENT_*.
local function parseMitigationString(text)
  if type(text) ~= "string" or text == "" then return nil, nil end

  local values, valueCount = {}, 0
  local cursor, length = 1, string_len(text)
  while cursor <= length do
    local separator = string_find(text, ",", cursor, true)
    local piece
    if separator then
      piece = string_sub(text, cursor, separator - 1)
      cursor = separator + 1
    else
      piece = string_sub(text, cursor)
      cursor = length + 1
    end
    valueCount = valueCount + 1
    values[valueCount] = tonumber(piece) or 0
  end

  return pickMitigation(values[1], values[2], values[3])
end

-- Recording -----------------------------------------------------------------

local function recordDamage(sourceGUID, targetGUID, amount, spellName, spellID, school, critical, mitigationType, mitigationAmount)
  amount = tonumber(amount) or 0
  local sourceName = resolveName(sourceGUID)
  local targetName = resolveName(targetGUID)
  if not sourceName and not targetName then return end

  Skada.Data:RecordDamage(sourceName, targetName, amount, spellName, spellID,
    school or "Physical", critical, GetTime(), mitigationType, mitigationAmount)
end

local function recordAvoidance(sourceGUID, targetGUID, spellName, avoidanceType)
  local sourceName = resolveName(sourceGUID)
  local targetName = resolveName(targetGUID)
  if not sourceName or not targetName then return end
  Skada.Data:RecordMiss(sourceName, targetName, spellName, avoidanceType, GetTime())
end

-- Handlers ------------------------------------------------------------------

local function onSpellDamage(targetGUID, casterGUID, spellID, amount, mitigationStr, hitInfo, spellSchool, effectAuraStr)
  local mitigationType, mitigationAmount = parseMitigationString(mitigationStr)
  local critical = hasFlag(hitInfo, SPELL_HITINFO_CRITICAL)
  recordDamage(casterGUID, targetGUID, amount, resolveSpellName(spellID), tonumber(spellID),
    SCHOOL_NAMES[tonumber(spellSchool) or -1], critical, mitigationType, mitigationAmount)
end

local function onAutoAttack(attackerGUID, targetGUID, totalDamage, hitInfo, victimState,
                            subDamageCount, blockedAmount, totalAbsorb, totalResist)
  local spellName = hasFlag(hitInfo, HITINFO_LEFTSWING) and "Auto Attack (Off-Hand)" or "Auto Attack"

  local avoidanceType = VICTIMSTATE_AVOIDANCE[tonumber(victimState) or -1]
  if not avoidanceType and hasFlag(hitInfo, HITINFO_MISS) then avoidanceType = "Miss" end
  if avoidanceType then
    recordAvoidance(attackerGUID, targetGUID, spellName, avoidanceType)
    return
  end

  local mitigationType, mitigationAmount = pickMitigation(totalAbsorb, blockedAmount, totalResist)
  if not mitigationType then
    -- Chat reports glancing and crushing without a number; keep that shape so
    -- the mitigation breakdown stays comparable across both sources.
    if hasFlag(hitInfo, HITINFO_GLANCING) then mitigationType, mitigationAmount = "glancing", 0 end
    if hasFlag(hitInfo, HITINFO_CRUSHING) then mitigationType, mitigationAmount = "crushing", 0 end
  end

  recordDamage(attackerGUID, targetGUID, totalDamage, spellName, nil, "Physical",
    hasFlag(hitInfo, HITINFO_CRITICALHIT), mitigationType, mitigationAmount)
end

local function onSpellMiss(casterGUID, targetGUID, spellID, missInfo)
  local avoidanceType = SPELL_MISS_NAMES[tonumber(missInfo) or -1]
  if not avoidanceType then return end
  recordAvoidance(casterGUID, targetGUID, resolveSpellName(spellID) or "Auto Attack", avoidanceType)
end

local function onSpellHeal(targetGUID, casterGUID, spellID, amount, critical, periodic)
  local casterName = resolveName(casterGUID)
  if not casterName then return end
  local targetName = resolveName(targetGUID)

  Skada.Data:RecordHealing(casterName, targetName, amount, resolveSpellName(spellID),
    tonumber(spellID), critical == 1, GetTime(), targetGUID)
end

local function onSpellEnergize(targetGUID, casterGUID, spellID, powerType, amount, periodic)
  local gainerName = resolveName(targetGUID)
  if not gainerName then return end

  local powerName = POWER_NAMES[tonumber(powerType) or -1]
  if not powerName then return end

  Skada.Data:RecordPower(gainerName, resolveName(casterGUID), amount, powerName,
    resolveSpellName(spellID) or powerName, tonumber(spellID), GetTime())
end

local function onEnvironmentalDamage(unitGUID, damageType, damage, absorb, resist)
  local targetName = resolveName(unitGUID)
  if not targetName then return end

  local mitigationType, mitigationAmount = pickMitigation(absorb, 0, resist)
  local spellName = ENVIRONMENT_NAMES[tonumber(damageType) or -1] or "Environment"
  -- The environment has no actor. Naming the victim as its own source marks the
  -- hit as self damage, which records damage taken without inventing a damage
  -- dealer; a nil source would otherwise fall through to the active player.
  Skada.Data:RecordDamage(targetName, targetName, damage, spellName, nil, "Physical", false,
    GetTime(), mitigationType, mitigationAmount)
end

local function onDamageShield(unitGUID, targetGUID, damage, spellSchool)
  local school = SCHOOL_NAMES[tonumber(spellSchool) or -1] or "Physical"
  recordDamage(unitGUID, targetGUID, damage, "Reflect (" .. school .. ")", nil, school, false)
end

local function onDispel(casterGUID, targetGUID, spellID)
  local casterName = resolveName(casterGUID)
  if not casterName then return end
  local targetName = resolveName(targetGUID)
  local auraName = resolveSpellName(spellID)

  Skada.Data:RecordDispel(casterName, targetName, auraName or "Dispel", auraName,
    tonumber(spellID), GetTime())
end

local function onUnitDied(guid)
  local targetName = resolveName(guid)
  if not targetName then return end
  local lastDamage = Skada.Tracking and Skada.Tracking:GetLastDamageInfo(targetName)
  Skada.Data:RecordDeath(targetName, GetTime(), lastDamage and lastDamage.sourceName,
    lastDamage and lastDamage.spellName)
  forgetName(guid)
end

-- Registration --------------------------------------------------------------

-- Nampower 4.5.0 and later enable an event as soon as something registers it.
-- Older builds need these CVars, and setting them on a new build is harmless.
local LEGACY_CVARS = {
  "NP_EnableSpellHealEvents",
  "NP_EnableSpellEnergizeEvents",
  "NP_EnableAutoAttackEvents",
  "NP_EnableSpellGoEvents",
}

local handlers = {
  SPELL_DAMAGE_EVENT_SELF = onSpellDamage,
  SPELL_DAMAGE_EVENT_OTHER = onSpellDamage,
  AUTO_ATTACK_SELF = onAutoAttack,
  AUTO_ATTACK_OTHER = onAutoAttack,
  SPELL_MISS_SELF = onSpellMiss,
  SPELL_MISS_OTHER = onSpellMiss,
  SPELL_HEAL_BY_SELF = onSpellHeal,
  SPELL_HEAL_BY_OTHER = onSpellHeal,
  SPELL_ENERGIZE_BY_SELF = onSpellEnergize,
  SPELL_ENERGIZE_BY_OTHER = onSpellEnergize,
  ENVIRONMENTAL_DMG_SELF = onEnvironmentalDamage,
  ENVIRONMENTAL_DMG_OTHER = onEnvironmentalDamage,
  DAMAGE_SHIELD_SELF = onDamageShield,
  DAMAGE_SHIELD_OTHER = onDamageShield,
  SPELL_DISPEL_BY_SELF = onDispel,
  SPELL_DISPEL_BY_OTHER = onDispel,
  UNIT_DIED = onUnitDied,
}

-- The _GUID unit events are deliberately not registered. Nampower warns that
-- they fire for every unit the client tracks and flood busy zones, and they buy
-- nothing here: any unit that produces a death has already been named by the
-- combat event that damaged it.

-- Skada's shared event frame forwards seven payload arguments and gates
-- registration on C_EventUtils.IsEventValid, which does not know about
-- Nampower's custom event codes. AUTO_ATTACK_* carries nine. This module
-- therefore owns its own frame and reads the payload directly.
local eventFrame = CreateFrame("Frame", "SkadaNampowerEventFrame")
Nampower.frame = eventFrame

eventFrame:SetScript("OnEvent", function(self, eventName, one, two, three, four, five, six, seven, eight, nine)
  if not eventName then
    eventName = event
    one, two, three, four, five, six, seven, eight, nine = arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9
  end

  local handler = handlers[eventName]
  if not handler then return end
  if not Skada.initialized or not Nampower.active then return end

  Nampower.eventCount = Nampower.eventCount + 1
  local ok, message = pcall(handler, one, two, three, four, five, six, seven, eight, nine)
  if not ok then
    Skada:Print("Nampower handler failed (" .. eventName .. "): " .. tostring(message))
  end
end)

-- Facts the parser must stop producing once Nampower is authoritative. Aura
-- uptime, crowd control and interrupts are absent from Nampower's event set and
-- keep flowing from chat text.
local SUPPRESSED_PARSER_FACTS = { "damage", "healing", "power", "avoidance", "dispel", "death" }

function Nampower:Probe()
  if type(GetNampowerVersion) ~= "function" then
    self.reason = "Nampower not loaded"
    return false
  end

  local ok, version = pcall(GetNampowerVersion)
  self.version = ok and version or nil

  -- Every aggregate is keyed by actor name, so GUID-only events are useless
  -- without the SuperWoW-style UnitName(guid) extension this client ships.
  local playerGUID = UnitGUID and UnitGUID("player")
  if not isRealGUID(playerGUID) then
    self.reason = "UnitGUID unavailable"
    return false
  end
  local probedName = UnitName(playerGUID)
  if probedName ~= UnitName("player") then
    self.reason = "UnitName(guid) unsupported"
    return false
  end

  self.available = true
  self.reason = "available"
  return true
end

function Nampower:Enable()
  if self.active then return true end
  if not self.available and not self:Probe() then return false end

  if SetCVar then
    local cvarIndex
    for cvarIndex = 1, table.getn(LEGACY_CVARS) do
      pcall(SetCVar, LEGACY_CVARS[cvarIndex], "1")
    end
  end

  local eventName
  for eventName in pairs(handlers) do
    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
  end

  self.active = true
  self.reason = "active"

  local factIndex
  for factIndex = 1, table.getn(SUPPRESSED_PARSER_FACTS) do
    Skada.Parser:SuppressFact(SUPPRESSED_PARSER_FACTS[factIndex], true)
  end

  return true
end

function Nampower:Disable()
  if not self.active then return end

  local eventName
  for eventName in pairs(handlers) do
    pcall(eventFrame.UnregisterEvent, eventFrame, eventName)
  end

  self.active = false
  self.reason = self.available and "disabled" or self.reason

  local factIndex
  for factIndex = 1, table.getn(SUPPRESSED_PARSER_FACTS) do
    Skada.Parser:SuppressFact(SUPPRESSED_PARSER_FACTS[factIndex], false)
  end
end

function Nampower:ApplySetting()
  local wanted = Skada.db and Skada.db.profile and Skada.db.profile.useNampower
  if wanted == nil then wanted = true end
  if wanted then self:Enable() else self:Disable() end
end

function Nampower:GetStatusText()
  if not self.available then return "chat text (" .. self.reason .. ")" end
  if not self.active then return "chat text (Nampower off)" end
  return "Nampower events (" .. self.eventCount .. " seen)"
end

resolveName = function(guid) return Nampower:ResolveName(guid) end
resolveSpellName = function(spellID) return Nampower:ResolveSpellName(spellID) end

Skada:RegisterEvent("PLAYER_LOGIN", function()
  Nampower:Probe()
  Nampower:ApplySetting()
end)

Skada:RegisterEvent("PLAYER_ENTERING_WORLD", function()
  Nampower:ApplySetting()
end)
