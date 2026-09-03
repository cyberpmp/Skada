local Skada = (_G or getfenv(0)).Skada

local Parser = { routes = {}, unmatchedCountByEvent = {} }
Skada.Parser = Parser

local type = type
local tonumber = tonumber
local table_getn = table.getn
local table_insert = table.insert
local string_sub = string.sub
local string_find = string.find
local string_len = string.len

local mitigationType, mitigationAmount

local PATTERN_MAGIC_CHARACTERS = {
  ["^"] = true, ["$"] = true, ["("] = true, [")"] = true,
  ["."] = true, ["["] = true, ["]"] = true, ["*"] = true,
  ["+"] = true, ["-"] = true, ["?"] = true,
}

local function compileCombatFormat(format)
  local outputPattern = "^"
  local sampleMessage = ""
  local capturePositions = {}
  local captureCount = 0
  local automaticIndex = 1
  local length = string_len(format)
  local cursor = 1

  while cursor <= length do
    local char = string_sub(format, cursor, cursor)
    if char ~= "%" then
      if PATTERN_MAGIC_CHARACTERS[char] then outputPattern = outputPattern .. "%" end
      outputPattern = outputPattern .. char
      sampleMessage = sampleMessage .. char
      cursor = cursor + 1
    else
      local nextChar = string_sub(format, cursor + 1, cursor + 1)
      if nextChar == "%" then
        outputPattern = outputPattern .. "%%"
        sampleMessage = sampleMessage .. "%"
        cursor = cursor + 2
      else
        local specCursor = cursor + 1
        local digits = ""
        while specCursor <= length do
          local digit = string_sub(format, specCursor, specCursor)
          if not string_find(digit, "%d") then break end
          digits = digits .. digit
          specCursor = specCursor + 1
        end

        local explicitIndex
        if digits ~= "" and string_sub(format, specCursor, specCursor) == "$" then
          explicitIndex = tonumber(digits)
          specCursor = specCursor + 1
        else
          specCursor = cursor + 1
        end

        while specCursor <= length do
          local flag = string_sub(format, specCursor, specCursor)
          if string_find(flag, "[%d%.%-%+%s]") then specCursor = specCursor + 1 else break end
        end
        local specifier = string_sub(format, specCursor, specCursor)
        captureCount = captureCount + 1
        if explicitIndex then
          capturePositions[explicitIndex] = captureCount
        else
          while capturePositions[automaticIndex] do
            automaticIndex = automaticIndex + 1
          end
          capturePositions[automaticIndex] = captureCount
          automaticIndex = automaticIndex + 1
        end

        if specifier == "d" or specifier == "i" then
          outputPattern = outputPattern .. "([%-]?%d+)"
          sampleMessage = sampleMessage .. "1"
        elseif specifier == "u" then
          outputPattern = outputPattern .. "(%d+)"
          sampleMessage = sampleMessage .. "1"
        elseif specifier == "f" or specifier == "g" then
          outputPattern = outputPattern .. "([%-]?[%d%.]+)"
          sampleMessage = sampleMessage .. "1"
        else
          outputPattern = outputPattern .. "(.-)"
          sampleMessage = sampleMessage .. "sample"
        end
        cursor = specCursor + 1
      end
    end
  end

  return outputPattern .. "$", capturePositions, sampleMessage, captureCount
end

local function captureAt(index, first, second, third, fourth, fifth)
  if index == 1 then return first end
  if index == 2 then return second end
  if index == 3 then return third end
  if index == 4 then return fourth end
  if index == 5 then return fifth end
end

function Parser:AddPattern(events, format, handler, critical, key)
  if type(format) ~= "string" or format == "" then return end
  local pattern, positions, sampleMessage, captureCount = compileCombatFormat(format)
  local directCaptures = true
  local positionIndex
  for positionIndex = 1, captureCount do
    if positions[positionIndex] ~= positionIndex then
      directCaptures = false
      break
    end
  end
  local entry = {
    pattern = pattern,
    positions = not directCaptures and positions or nil,
    sampleMessage = sampleMessage,
    handler = handler,
    critical = critical and true or false,
    key = key or format,
    directCaptures = directCaptures,
  }

  local eventIndex, eventName, route
  for eventIndex = 1, table_getn(events) do
    eventName = events[eventIndex]
    route = self.routes[eventName]
    if not route then
      route = {}
      route.priorityEntriesByEntry = {}
      self.routes[eventName] = route
      Skada:RegisterEvent(eventName, function(event, message) Parser:OnCombatMessage(event, message) end)
    end
    local priorityEntries = {}
    local previousIndex, previousEntry
    for previousIndex = 1, table_getn(route) do
      previousEntry = route[previousIndex]
      if string_find(previousEntry.sampleMessage, entry.pattern) then
        table_insert(priorityEntries, previousEntry)
      end
    end
    route.priorityEntriesByEntry[entry] = priorityEntries
    table_insert(route, entry)
  end
end

function Parser:AddGlobal(events, globalName, handler)
  self:AddPattern(events, _G[globalName], handler, string_find(globalName, "CRIT") ~= nil, globalName)
end

function Parser:Match(entry, message)
  local start, _, first, second, third, fourth, fifth = string_find(message, entry.pattern)
  if not start then return false end
  if entry.directCaptures then return true, first, second, third, fourth, fifth end
  local positions = entry.positions
  return true,
    captureAt(positions[1], first, second, third, fourth, fifth),
    captureAt(positions[2], first, second, third, fourth, fifth),
    captureAt(positions[3], first, second, third, fourth, fifth),
    captureAt(positions[4], first, second, third, fourth, fifth),
    captureAt(positions[5], first, second, third, fourth, fifth)
end

local mitigationTrailers = {
  { pattern = " %((%d+) absorbed%)$", trailerType = "absorbed" },
  { pattern = " %((%d+) resisted%)$", trailerType = "resisted" },
  { pattern = " %((%d+) blocked%)$", trailerType = "blocked" },
  { pattern = " %(glancing%)$", trailerType = "glancing" },
  { pattern = " %(crushing%)$", trailerType = "crushing" },
}

function Parser:OnCombatMessage(eventName, message)
  if type(message) ~= "string" then return end
  local route = self.routes[eventName]
  if not route then return end

  mitigationType, mitigationAmount = nil, nil

  if string_sub(message, -1) == ")" then
    local trailerIndex
    for trailerIndex = 1, table_getn(mitigationTrailers) do
      local trailer = mitigationTrailers[trailerIndex]
      local start, _, amount = string_find(message, trailer.pattern)
      if start then
        mitigationType = trailer.trailerType
        mitigationAmount = tonumber(amount) or 0
        message = string_sub(message, 1, start - 1)
        break
      end
    end
  end

  local matched, first, second, third, fourth, fifth
  local cachedEntry = route.lastMatchedEntry
  if cachedEntry then
    matched, first, second, third, fourth, fifth = self:Match(cachedEntry, message)
    if matched then
      local cachedFirst, cachedSecond, cachedThird, cachedFourth, cachedFifth = first, second, third, fourth, fifth
      local priorityEntries = route.priorityEntriesByEntry and route.priorityEntriesByEntry[cachedEntry] or {}
      local priorityIndex, priorityEntry
      for priorityIndex = 1, table_getn(priorityEntries) do
        priorityEntry = priorityEntries[priorityIndex]
        matched, first, second, third, fourth, fifth = self:Match(priorityEntry, message)
        if matched then
          route.lastMatchedEntry = priorityEntry
          priorityEntry.handler(priorityEntry, first, second, third, fourth, fifth)
          return true
        end
      end
      cachedEntry.handler(cachedEntry, cachedFirst, cachedSecond, cachedThird, cachedFourth, cachedFifth)
      return true
    end
  end

  local formatEntry, formatIndex
  for formatIndex = 1, table_getn(route) do
    formatEntry = route[formatIndex]
    if formatEntry ~= cachedEntry then
      matched, first, second, third, fourth, fifth = self:Match(formatEntry, message)
      if matched then
        route.lastMatchedEntry = formatEntry
        formatEntry.handler(formatEntry, first, second, third, fourth, fifth)
        return true
      end
    end
  end
  route.lastMatchedEntry = nil
  self.unmatchedCountByEvent[eventName] = (self.unmatchedCountByEvent[eventName] or 0) + 1
end

local function getPlayerName()
  return Skada.Data:GetPlayerName()
end

local function resolveSpellID(sourceName, spellName)
  return Skada.Tracking and Skada.Tracking:GetSpellID(sourceName, spellName) or nil
end

local function recordDamage(sourceName, spellName, targetName, amount, school, critical)
  Skada.Data:RecordDamage(sourceName, targetName, amount, spellName, resolveSpellID(sourceName, spellName),
    school or "Physical", critical, GetTime(), mitigationType, mitigationAmount)
end

local function recordHealing(sourceName, spellName, targetName, amount, critical)
  Skada.Data:RecordHealing(sourceName, targetName, amount, spellName,
    resolveSpellID(sourceName, spellName), critical, GetTime())
end

local function recordPower(recipientName, sourceName, amount, powerType, spellName)
  Skada.Data:RecordPower(recipientName, sourceName, amount, powerType, spellName,
    resolveSpellID(sourceName, spellName), GetTime())
end

local function recordAvoidance(sourceName, spellName, targetName, avoidanceType)
  Skada.Data:RecordMiss(sourceName, targetName, spellName, avoidanceType, GetTime())
end

local function spellSchoolSelfSelf(formatEntry, spellName, amount, school)
  recordDamage(getPlayerName(), spellName, getPlayerName(), amount, school, formatEntry.critical)
end
local function spellSelfSelf(formatEntry, spellName, amount)
  recordDamage(getPlayerName(), spellName, getPlayerName(), amount, "Physical", formatEntry.critical)
end
local function periodicSelfSelf(_, amount, school, spellName)
  recordDamage(getPlayerName(), spellName, getPlayerName(), amount, school, false)
end
local function spellSchoolSelfOther(formatEntry, spellName, targetName, amount, school)
  recordDamage(getPlayerName(), spellName, targetName, amount, school, formatEntry.critical)
end
local function spellSelfOther(formatEntry, spellName, targetName, amount)
  recordDamage(getPlayerName(), spellName, targetName, amount, "Physical", formatEntry.critical)
end
local function periodicSelfOther(_, targetName, amount, school, spellName)
  recordDamage(getPlayerName(), spellName, targetName, amount, school, false)
end

local function autoSelfOther(formatEntry, targetName, amount, school)
  recordDamage(getPlayerName(), "Auto Attack", targetName, amount, school, formatEntry.critical)
end
local function shieldSelfOther(_, amount, school, targetName)
  recordDamage(getPlayerName(), "Reflect (" .. (school or "Physical") .. ")", targetName, amount, school, false)
end

local function spellSchoolOtherSelf(formatEntry, sourceName, spellName, amount, school)
  recordDamage(sourceName, spellName, getPlayerName(), amount, school, formatEntry.critical)
end
local function spellOtherSelf(formatEntry, sourceName, spellName, amount)
  recordDamage(sourceName, spellName, getPlayerName(), amount, "Physical", formatEntry.critical)
end
local function periodicOtherSelf(_, amount, school, sourceName, spellName)
  recordDamage(sourceName, spellName, getPlayerName(), amount, school, false)
end
local function autoOtherSelf(formatEntry, sourceName, amount, school)
  recordDamage(sourceName, "Auto Attack", getPlayerName(), amount, school, formatEntry.critical)
end
local function shieldOtherSelf(_, sourceName, amount, school)
  recordDamage(sourceName, "Reflect (" .. (school or "Physical") .. ")", getPlayerName(), amount, school, false)
end

local function spellSchoolOtherOther(formatEntry, sourceName, spellName, targetName, amount, school)
  recordDamage(sourceName, spellName, targetName, amount, school, formatEntry.critical)
end
local function spellOtherOther(formatEntry, sourceName, spellName, targetName, amount)
  recordDamage(sourceName, spellName, targetName, amount, "Physical", formatEntry.critical)
end
local function periodicOtherOther(_, targetName, amount, school, sourceName, spellName)
  recordDamage(sourceName, spellName, targetName, amount, school, false)
end
local function autoOtherOther(formatEntry, sourceName, targetName, amount, school)
  recordDamage(sourceName, "Auto Attack", targetName, amount, school, formatEntry.critical)
end
local function shieldOtherOther(_, sourceName, amount, school, targetName)
  recordDamage(sourceName, "Reflect (" .. (school or "Physical") .. ")", targetName, amount, school, false)
end

local function healOtherSelf(formatEntry, sourceName, spellName, amount)
  recordHealing(sourceName, spellName, getPlayerName(), amount, formatEntry.critical)
end
local function periodicHealOtherSelf(_, amount, sourceName, spellName)
  recordHealing(sourceName, spellName, getPlayerName(), amount, false)
end
local function healSelfSelf(formatEntry, spellName, amount)
  recordHealing(getPlayerName(), spellName, getPlayerName(), amount, formatEntry.critical)
end
local function periodicHealSelfSelf(_, amount, spellName)
  recordHealing(getPlayerName(), spellName, getPlayerName(), amount, false)
end
local function healSelfOther(formatEntry, spellName, targetName, amount)
  recordHealing(getPlayerName(), spellName, targetName, amount, formatEntry.critical)
end
local function periodicHealSelfOther(_, targetName, amount, spellName)
  recordHealing(getPlayerName(), spellName, targetName, amount, false)
end
local function healOtherOther(formatEntry, sourceName, spellName, targetName, amount)
  recordHealing(sourceName, spellName, targetName, amount, formatEntry.critical)
end
local function periodicHealOtherOther(_, targetName, amount, sourceName, spellName)
  recordHealing(sourceName, spellName, targetName, amount, false)
end

local selfHitEvents = { "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_SELF_MISSES" }
local otherSelfHitEvents = { "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_SPELL_CREATURE_VS_SELF_MISSES" }
local otherOtherHitEvents = {
  "CHAT_MSG_COMBAT_PARTY_HITS", "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
  "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS", "CHAT_MSG_COMBAT_PET_HITS",
  "CHAT_MSG_SPELL_PARTY_MISSES", "CHAT_MSG_SPELL_FRIENDLYPLAYER_MISSES",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_MISSES", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_MISSES",
  "CHAT_MSG_SPELL_CREATURE_VS_PARTY_MISSES", "CHAT_MSG_SPELL_PET_MISSES",
}
local selfSpellEvents = { "CHAT_MSG_SPELL_SELF_DAMAGE" }
local otherSelfSpellEvents = { "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" }
local otherOtherSpellEvents = {
  "CHAT_MSG_SPELL_PARTY_DAMAGE", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_PET_DAMAGE",
}
local periodicOtherEvents = {
  "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
}

Parser:AddGlobal(selfHitEvents, "COMBATHITSELFOTHER", autoSelfOther)
Parser:AddGlobal(selfHitEvents, "COMBATHITSCHOOLSELFOTHER", autoSelfOther)
Parser:AddGlobal(selfHitEvents, "COMBATHITCRITSELFOTHER", autoSelfOther)
Parser:AddGlobal(selfHitEvents, "COMBATHITCRITSCHOOLSELFOTHER", autoSelfOther)

Parser:AddGlobal(otherSelfHitEvents, "COMBATHITOTHERSELF", autoOtherSelf)
Parser:AddGlobal(otherSelfHitEvents, "COMBATHITSCHOOLOTHERSELF", autoOtherSelf)
Parser:AddGlobal(otherSelfHitEvents, "COMBATHITCRITOTHERSELF", autoOtherSelf)
Parser:AddGlobal(otherSelfHitEvents, "COMBATHITCRITSCHOOLOTHERSELF", autoOtherSelf)

Parser:AddGlobal(otherOtherHitEvents, "COMBATHITOTHEROTHER", autoOtherOther)
Parser:AddGlobal(otherOtherHitEvents, "COMBATHITSCHOOLOTHEROTHER", autoOtherOther)
Parser:AddGlobal(otherOtherHitEvents, "COMBATHITCRITOTHEROTHER", autoOtherOther)
Parser:AddGlobal(otherOtherHitEvents, "COMBATHITCRITSCHOOLOTHEROTHER", autoOtherOther)

Parser:AddGlobal(selfSpellEvents, "SPELLLOGSCHOOLSELFSELF", spellSchoolSelfSelf)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGCRITSCHOOLSELFSELF", spellSchoolSelfSelf)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGSELFSELF", spellSelfSelf)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGCRITSELFSELF", spellSelfSelf)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGSCHOOLSELFOTHER", spellSchoolSelfOther)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGCRITSCHOOLSELFOTHER", spellSchoolSelfOther)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGSELFOTHER", spellSelfOther)
Parser:AddGlobal(selfSpellEvents, "SPELLLOGCRITSELFOTHER", spellSelfOther)

Parser:AddGlobal(otherSelfSpellEvents, "SPELLLOGSCHOOLOTHERSELF", spellSchoolOtherSelf)
Parser:AddGlobal(otherSelfSpellEvents, "SPELLLOGCRITSCHOOLOTHERSELF", spellSchoolOtherSelf)
Parser:AddGlobal(otherSelfSpellEvents, "SPELLLOGOTHERSELF", spellOtherSelf)
Parser:AddGlobal(otherSelfSpellEvents, "SPELLLOGCRITOTHERSELF", spellOtherSelf)

Parser:AddGlobal(otherOtherSpellEvents, "SPELLLOGSCHOOLOTHEROTHER", spellSchoolOtherOther)
Parser:AddGlobal(otherOtherSpellEvents, "SPELLLOGCRITSCHOOLOTHEROTHER", spellSchoolOtherOther)
Parser:AddGlobal(otherOtherSpellEvents, "SPELLLOGOTHEROTHER", spellOtherOther)
Parser:AddGlobal(otherOtherSpellEvents, "SPELLLOGCRITOTHEROTHER", spellOtherOther)

Parser:AddGlobal({ "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" }, "DAMAGESHIELDSELFOTHER", shieldSelfOther)
Parser:AddGlobal({ "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS" }, "DAMAGESHIELDOTHERSELF", shieldOtherSelf)
Parser:AddGlobal({ "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS" }, "DAMAGESHIELDOTHEROTHER", shieldOtherOther)

Parser:AddGlobal(periodicOtherEvents, "PERIODICAURADAMAGESELFOTHER", periodicSelfOther)
Parser:AddGlobal(periodicOtherEvents, "PERIODICAURADAMAGEOTHEROTHER", periodicOtherOther)
Parser:AddGlobal({ "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" }, "PERIODICAURADAMAGESELFSELF", periodicSelfSelf)
Parser:AddGlobal({ "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" }, "PERIODICAURADAMAGEOTHERSELF", periodicOtherSelf)

local function missSelfOther(_, targetName) recordAvoidance(getPlayerName(), "Auto Attack", targetName, "Miss") end
local function dodgeSelfOther(_, targetName) recordAvoidance(getPlayerName(), "Auto Attack", targetName, "Dodge") end
local function parrySelfOther(_, targetName) recordAvoidance(getPlayerName(), "Auto Attack", targetName, "Parry") end
local function immuneSelfOther(_, targetName) recordAvoidance(getPlayerName(), "Auto Attack", targetName, "Immune") end

local function missOtherSelf(_, sourceName) recordAvoidance(sourceName, "Auto Attack", getPlayerName(), "Miss") end
local function dodgeOtherSelf(_, sourceName) recordAvoidance(sourceName, "Auto Attack", getPlayerName(), "Dodge") end
local function parryOtherSelf(_, sourceName) recordAvoidance(sourceName, "Auto Attack", getPlayerName(), "Parry") end
local function immuneOtherSelf(_, sourceName) recordAvoidance(sourceName, "Auto Attack", getPlayerName(), "Immune") end

local function missOtherOther(_, sourceName, targetName) recordAvoidance(sourceName, "Auto Attack", targetName, "Miss") end
local function dodgeOtherOther(_, sourceName, targetName) recordAvoidance(sourceName, "Auto Attack", targetName, "Dodge") end
local function parryOtherOther(_, sourceName, targetName) recordAvoidance(sourceName, "Auto Attack", targetName, "Parry") end
local function immuneOtherOther(_, sourceName, targetName) recordAvoidance(sourceName, "Auto Attack", targetName, "Immune") end

local function spellMissSelfOther(_, spellName, targetName) recordAvoidance(getPlayerName(), spellName, targetName, "Miss") end
local function spellResistSelfOther(_, spellName, targetName) recordAvoidance(getPlayerName(), spellName, targetName, "Resist") end
local function spellImmuneSelfOther(_, spellName, targetName) recordAvoidance(getPlayerName(), spellName, targetName, "Immune") end
local function spellImmuneSelfOtherAlt(_, targetName, spellName) recordAvoidance(getPlayerName(), spellName, targetName, "Immune") end

local function spellMissOtherSelf(_, sourceName, spellName) recordAvoidance(sourceName, spellName, getPlayerName(), "Miss") end
local function spellResistOtherSelf(_, sourceName, spellName) recordAvoidance(sourceName, spellName, getPlayerName(), "Resist") end
local function spellImmuneOtherSelf(_, sourceName, spellName) recordAvoidance(sourceName, spellName, getPlayerName(), "Immune") end

local function spellMissOtherOther(_, sourceName, spellName, targetName) recordAvoidance(sourceName, spellName, targetName, "Miss") end
local function spellResistOtherOther(_, sourceName, spellName, targetName) recordAvoidance(sourceName, spellName, targetName, "Resist") end
local function spellImmuneOtherOther(_, sourceName, spellName, targetName) recordAvoidance(sourceName, spellName, targetName, "Immune") end

Parser:AddPattern(selfHitEvents, "You miss %s.", missSelfOther, false, "MISS_EN_SELFOTHER")
Parser:AddPattern(selfHitEvents, "You attack. %s dodges.", dodgeSelfOther, false, "DODGE_EN_SELFOTHER")
Parser:AddPattern(selfHitEvents, "You attack. %s parries.", parrySelfOther, false, "PARRY_EN_SELFOTHER")
Parser:AddPattern(selfHitEvents, "You attack but %s is immune.", immuneSelfOther, false, "IMMUNE_EN_SELFOTHER")

Parser:AddPattern(otherSelfHitEvents, "%s misses you.", missOtherSelf, false, "MISS_EN_OTHERSELF")
Parser:AddPattern(otherSelfHitEvents, "%s attacks. You dodge.", dodgeOtherSelf, false, "DODGE_EN_OTHERSELF")
Parser:AddPattern(otherSelfHitEvents, "%s attacks. You parry.", parryOtherSelf, false, "PARRY_EN_OTHERSELF")
Parser:AddPattern(otherSelfHitEvents, "%s attacks but you are immune.", immuneOtherSelf, false, "IMMUNE_EN_OTHERSELF")

Parser:AddPattern(otherOtherHitEvents, "%s misses %s.", missOtherOther, false, "MISS_EN_OTHEROTHER")
Parser:AddPattern(otherOtherHitEvents, "%s attacks. %s dodges.", dodgeOtherOther, false, "DODGE_EN_OTHEROTHER")
Parser:AddPattern(otherOtherHitEvents, "%s attacks. %s parries.", parryOtherOther, false, "PARRY_EN_OTHEROTHER")
Parser:AddPattern(otherOtherHitEvents, "%s attacks but %s is immune.", immuneOtherOther, false, "IMMUNE_EN_OTHEROTHER")

Parser:AddPattern(selfSpellEvents, "Your %s misses %s.", spellMissSelfOther, false, "SPELLMISS_EN_SELFOTHER")
Parser:AddPattern(selfSpellEvents, "Your %s was resisted by %s.", spellResistSelfOther, false, "SPELLRESIST_EN_SELFOTHER")
Parser:AddPattern(selfSpellEvents, "Your %s fails. %s is immune.", spellImmuneSelfOther, false, "SPELLIMMUNE_EN_SELFOTHER")
Parser:AddPattern(selfSpellEvents, "%s is immune to your %s.", spellImmuneSelfOtherAlt, false, "SPELLIMMUNE_EN_SELFOTHER_ALT")

Parser:AddPattern(otherSelfSpellEvents, "%s's %s misses you.", spellMissOtherSelf, false, "SPELLMISS_EN_OTHERSELF")
Parser:AddPattern(otherSelfSpellEvents, "%s's %s was resisted.", spellResistOtherSelf, false, "SPELLRESIST_EN_OTHERSELF")
Parser:AddPattern(otherSelfSpellEvents, "%s's %s fails. You are immune.", spellImmuneOtherSelf, false, "SPELLIMMUNE_EN_OTHERSELF")

Parser:AddPattern(otherOtherSpellEvents, "%s's %s misses %s.", spellMissOtherOther, false, "SPELLMISS_EN_OTHEROTHER")
Parser:AddPattern(otherOtherSpellEvents, "%s's %s was resisted by %s.", spellResistOtherOther, false, "SPELLRESIST_EN_OTHEROTHER")
Parser:AddPattern(otherOtherSpellEvents, "%s's %s fails. %s is immune.", spellImmuneOtherOther, false, "SPELLIMMUNE_EN_OTHEROTHER")

local selfHealEvents = { "CHAT_MSG_SPELL_SELF_BUFF" }
local otherHealEvents = {
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF", "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
  "CHAT_MSG_SPELL_PARTY_BUFF",
}
local periodicOtherHealEvents = {
  "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS",
}

Parser:AddGlobal(selfHealEvents, "HEALEDCRITSELFSELF", healSelfSelf)
Parser:AddGlobal(selfHealEvents, "HEALEDSELFSELF", healSelfSelf)
Parser:AddGlobal(selfHealEvents, "HEALEDCRITSELFOTHER", healSelfOther)
Parser:AddGlobal(selfHealEvents, "HEALEDSELFOTHER", healSelfOther)
Parser:AddGlobal(otherHealEvents, "HEALEDCRITOTHERSELF", healOtherSelf)
Parser:AddGlobal(otherHealEvents, "HEALEDOTHERSELF", healOtherSelf)
Parser:AddGlobal(otherHealEvents, "HEALEDCRITOTHEROTHER", healOtherOther)
Parser:AddGlobal(otherHealEvents, "HEALEDOTHEROTHER", healOtherOther)
Parser:AddGlobal(periodicOtherHealEvents, "PERIODICAURAHEALSELFOTHER", periodicHealSelfOther)
Parser:AddGlobal(periodicOtherHealEvents, "PERIODICAURAHEALOTHEROTHER", periodicHealOtherOther)
Parser:AddGlobal({ "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" }, "PERIODICAURAHEALSELFSELF", periodicHealSelfSelf)
Parser:AddGlobal({ "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" }, "PERIODICAURAHEALOTHERSELF", periodicHealOtherSelf)

local function powerSelfSelf(_, amount, powerType, spellName)
  recordPower(getPlayerName(), getPlayerName(), amount, powerType, spellName)
end
local function powerSelfOther(_, targetName, amount, powerType, spellName)
  recordPower(targetName, getPlayerName(), amount, powerType, spellName)
end
local function powerOtherSelf(_, amount, powerType, sourceName, spellName)
  recordPower(getPlayerName(), sourceName, amount, powerType, spellName)
end
local function powerOtherOther(_, targetName, amount, powerType, sourceName, spellName)
  recordPower(targetName, sourceName, amount, powerType, spellName)
end

Parser:AddPattern(selfHealEvents, "You gain %d %s from %s's %s.", powerOtherSelf, false, "POWER_EN_OTHERSELF")
Parser:AddPattern(selfHealEvents, "You gain %d %s from %s.", powerSelfSelf, false, "POWER_EN_SELFSELF")
Parser:AddPattern(selfHealEvents, "%s gains %d %s from your %s.", powerSelfOther, false, "POWER_EN_SELFOTHER")
Parser:AddPattern({ "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" }, "You gain %d %s from %s's %s.", powerOtherSelf, false, "POWER_EN_OTHERSELF_PERIODIC")
Parser:AddPattern(otherHealEvents, "You gain %d %s from %s's %s.", powerOtherSelf, false, "POWER_EN_OTHERSELF")
Parser:AddPattern(otherHealEvents, "%s gains %d %s from %s's %s.", powerOtherOther, false, "POWER_EN_OTHEROTHER")
Parser:AddPattern(periodicOtherHealEvents, "%s gains %d %s from %s's %s.", powerOtherOther, false, "POWER_EN_OTHEROTHER_PERIODIC")

local interruptEvents = {
  "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_PET_DAMAGE",
}
local function interruptSelfOther(_, targetName, interruptedSpellName)
  Skada.Tracking:RecordRawInterrupt(getPlayerName(), targetName, interruptedSpellName, GetTime())
end
local function interruptOtherOther(_, sourceName, targetName, interruptedSpellName)
  Skada.Tracking:RecordRawInterrupt(sourceName, targetName, interruptedSpellName, GetTime())
end
local function interruptOtherSelf(_, sourceName, interruptedSpellName)
  Skada.Tracking:RecordRawInterrupt(sourceName, getPlayerName(), interruptedSpellName, GetTime())
end
Parser:AddGlobal(interruptEvents, "SPELLINTERRUPTSELFOTHER", interruptSelfOther)
Parser:AddGlobal(interruptEvents, "SPELLINTERRUPTOTHEROTHER", interruptOtherOther)
Parser:AddGlobal(interruptEvents, "SPELLINTERRUPTOTHERSELF", interruptOtherSelf)
Parser:AddPattern(interruptEvents, "You interrupt %s's %s.", interruptSelfOther, false, "INTERRUPT_EN_SELFOTHER")
Parser:AddPattern(interruptEvents, "%s interrupts %s's %s.", interruptOtherOther, false, "INTERRUPT_EN_OTHEROTHER")
Parser:AddPattern(interruptEvents, "%s interrupts your %s.", interruptOtherSelf, false, "INTERRUPT_EN_OTHERSELF")

local auraBreakEvents = { "CHAT_MSG_SPELL_BREAK_AURA" }
local function auraRemovedOther(_, targetName, auraName) Skada.Tracking:RecordRawDispel(targetName, auraName, GetTime()) end
local function auraRemovedSelf(_, auraName) Skada.Tracking:RecordRawDispel(getPlayerName(), auraName, GetTime()) end
Parser:AddPattern(auraBreakEvents, "%s's %s is removed.", auraRemovedOther, false, "AURA_REMOVED_EN_OTHER")
Parser:AddPattern(auraBreakEvents, "Your %s is removed.", auraRemovedSelf, false, "AURA_REMOVED_EN_SELF")

local deathEvents = { "CHAT_MSG_COMBAT_FRIENDLY_DEATH", "CHAT_MSG_COMBAT_HOSTILE_DEATH" }
local function deathOther(_, targetName)
  local lastDamage = Skada.Tracking and Skada.Tracking:GetLastDamageInfo(targetName)
  Skada.Data:RecordDeath(targetName, GetTime(), lastDamage and lastDamage.sourceName, lastDamage and lastDamage.spellName)
end
local function deathSelf()
  local playerName = getPlayerName()
  local lastDamage = Skada.Tracking and Skada.Tracking:GetLastDamageInfo(playerName)
  Skada.Data:RecordDeath(playerName, GetTime(), lastDamage and lastDamage.sourceName, lastDamage and lastDamage.spellName)
end
Parser:AddGlobal(deathEvents, "UNITDIESOTHER", deathOther)
Parser:AddGlobal(deathEvents, "UNITDIESSELF", deathSelf)
Parser:AddPattern(deathEvents, "%s dies.", deathOther, false, "DEATH_EN_OTHER")
Parser:AddPattern(deathEvents, "You die.", deathSelf, false, "DEATH_EN_SELF")

function Parser:GetMissCount()
  local total = 0
  local _, count
  for _, count in pairs(self.unmatchedCountByEvent) do total = total + count end
  return total
end
