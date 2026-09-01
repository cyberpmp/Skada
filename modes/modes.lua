local Skada = (_G or getfenv(0)).Skada

local Modes = { list = {}, byKey = {} }
Skada.Modes = Modes

local max = math.max
local min = math.min
local table_getn = table.getn

local DataNavigation = Skada.DataNavigation

local function formatUptime(activeDuration, segmentDuration, count)
  local percent = segmentDuration > 0 and min(100, activeDuration / segmentDuration * 100) or 0
  local text = string.format("%.1fs (%.0f%%)", activeDuration, percent)
  if count > 0 then text = text .. " x" .. count end
  return text
end

local function formatCount(count, duration)
  if duration then return tostring(count) .. " / " .. string.format("%.1fs", duration) end
  return tostring(count)
end

local function formatPercentPart(value, total)
  local percent = total > 0 and value / total * 100 or 0
  return string.format("%.1f%%", percent)
end

local function addMode(mode)
  Modes.list[table_getn(Modes.list) + 1] = mode
  Modes.byKey[mode.key] = mode
end

addMode({ key = "damage", title = "Damage", field = "damage", detail = "damageSpells" })
addMode({ key = "dps", title = "DPS", field = "damage", detail = "damageSpells", rate = true })
addMode({ key = "damagedTargets", title = "Damaged Targets", field = "damage", detail = "damageTargets" })
addMode({ key = "damageTaken", title = "Damage Taken", field = "damageTaken", detail = "takenSpells" })
addMode({ key = "healing", title = "Healing", field = "effectiveHealing", detail = "healingSpells", detailValueField = "effectiveHealing" })
addMode({ key = "hps", title = "HPS", field = "effectiveHealing", detail = "healingSpells", detailValueField = "effectiveHealing", rate = true })
addMode({ key = "overhealing", title = "Overhealing", field = "overhealing", detail = "healingSpells", detailValueField = "overhealing" })
addMode({ key = "healedTargets", title = "Healing Targets", field = "effectiveHealing", detail = "healTargets", detailValueField = "effectiveHealing" })
addMode({ key = "power", title = "Power Gained", field = "power", detail = "powerSpells" })
addMode({ key = "dispels", title = "Dispels", field = "dispels", detail = "dispelSpells", count = true })
addMode({ key = "interrupts", title = "Interrupts", field = "interrupts", detail = "interruptSpells", count = true })
addMode({ key = "cc", title = "CC Done", field = "cc", detail = "ccSpells", count = true, duration = true })
addMode({ key = "ccBreaks", title = "CC Breaks", field = "ccBreaks", detail = "ccBreakSpells", count = true })
addMode({ key = "debuffs", title = "Debuffs", field = "debuffUptime", detail = "debuffSpells", uptime = true, countField = "debuffs" })
addMode({ key = "buffs", title = "Buffs", field = "buffUptime", detail = "buffSpells", uptime = true, countField = "buffs" })
addMode({ key = "threat", title = "Threat", live = true })
addMode({ key = "deaths", title = "Deaths", field = "deaths", detail = "deathLog", count = true })

function Modes:Get(key)
  return self.byKey[key] or self.byKey.damage
end

function Modes:GetActorValue(mode, actor)
  if mode.live then return 0 end
  local value = actor[mode.field] or 0
  if mode.rate then value = value / max(1, actor.activeTime or 0) end
  return value
end

function Modes:GetSetTitle(mode, set)
  if mode.live then return "" end
  local raw = set[mode.field] or 0
  if mode.uptime then
    local count = mode.countField and (set[mode.countField] or 0) or 0
    return formatUptime(raw, Skada.Data:GetSetDuration(set), count)
  end
  if mode.count then
    return formatCount(raw, mode.duration and (set.ccDuration or 0) or nil)
  end
  if mode.rate then
    return Skada:FormatNumber(raw / max(1, Skada.Data:GetSetDuration(set)))
  end
  return Skada:FormatNumber(raw)
end

function Modes:GetActorText(mode, actor, set)
  if mode.live then return "" end
  local raw = actor[mode.field] or 0
  local value = self:GetActorValue(mode, actor)
  if mode.uptime then
    local count = mode.countField and (actor[mode.countField] or 0) or 0
    return formatUptime(raw, Skada.Data:GetSetDuration(set), count)
  end
  if mode.count then
    return formatCount(raw, mode.duration and (actor.ccDuration or 0) or nil)
  end
  if mode.rate then return Skada:FormatNumber(value) end

  local total = set[mode.field] or 0
  if mode.key == "damage" or mode.key == "healing" then
    local rate = raw / max(1, actor.activeTime or 0)
    return Skada:FormatNumber(raw) .. " (" .. Skada:FormatNumber(rate) .. ", " .. formatPercentPart(raw, total) .. ")"
  end
  return Skada:FormatNumber(raw) .. " (" .. formatPercentPart(raw, total) .. ")"
end

function Modes:GetDetailValue(mode, spell)
  if mode.detailValueField then return spell[mode.detailValueField] or 0 end
  return spell.amount or spell.count or 0
end

function Modes:GetDetailText(mode, spell, actor, set)
  if spell.customText then return spell.customText end
  local value = self:GetDetailValue(mode, spell)
  if mode.uptime then
    local duration = set and Skada.Data:GetSetDuration(set) or 0
    local percent = duration > 0 and min(100, (spell.duration or 0) / duration * 100) or 0
    return string.format("%.1fs (%.0f%%) x%d", spell.duration or 0, percent, value)
  end
  if mode.count then
    return formatCount(value, mode.duration and spell.duration or nil)
  end
  local total = actor[mode.field] or 0
  return Skada:FormatNumber(value) .. " (" .. formatPercentPart(value, total) .. ")"
end

function Modes:Cycle(direction, window)
  window = window or (Skada.UI and Skada.UI.GetActive and Skada.UI:GetActive())
  local config = window and window.db or Skada.db.profile
  local current = config.mode
  local index = 1
  local i
  for i = 1, table_getn(self.list) do
    if self.list[i].key == current then index = i break end
  end
  index = index + (direction or 1)
  if index > table_getn(self.list) then index = 1 end
  if index < 1 then index = table_getn(self.list) end
  return self:Set(self.list[index].key, window)
end

function Modes:IsTitle(name)
  local i
  for i = 1, table_getn(self.list) do
    if name == self.list[i].title then return true end
  end
  return false
end

-- A window keeps its own name once the user has renamed it; auto-named
-- windows (name still matching a mode title, or created from a mode) follow
-- the mode so the settings tree and window list stay truthful.
function Modes:IsAutoNamed(config)
  if config.nameIsCustom then return false end
  if config.name == nil then return true end
  return self:IsTitle(config.name)
end

-- Sets the mode and returns found, renamed so callers can refresh tree
-- labels only when an auto-name actually followed the mode.
function Modes:Set(value, window)
  if not value then return false, false end
  window = window or (Skada.UI and Skada.UI.GetActive and Skada.UI:GetActive())
  local config = window and window.db or Skada.db.profile
  local lowered = string.lower(value)
  local i, mode
  for i = 1, table_getn(self.list) do
    mode = self.list[i]
    if string.lower(mode.key) == lowered or string.lower(mode.title) == lowered then
      config.mode = mode.key
      if mode.live then config.segment = "current" end
      local renamed = false
      if window and window.db == config and self:IsAutoNamed(config) and config.name ~= mode.title then
        config.name = mode.title
        if window.title then window.title:SetText(config.name) end
        renamed = true
      end
      if window and window.db == config and Skada.Data and Skada.Data.clientInCombat
          and mode.key ~= config.combatMode then
        -- a mode picked by hand mid-fight wins over the pending combat restore
        window.restoreMode = nil
      end
      DataNavigation:OnModeChanged(window)
      Skada:MarkDirty()
      return true, renamed
    end
  end
  return false, false
end
