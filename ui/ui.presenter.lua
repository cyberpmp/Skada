local Skada = (_G or getfenv(0)).Skada

local Presenter = {}
Skada.UIPresenter = Presenter

local Common = Skada.Common
local getVisibleRowCount = Skada.WindowConfig.GetVisibleRowCount

local pairs = pairs
local floor = math.floor
local max = math.max
local table_getn = table.getn
local table_sort = table.sort

local function sortEntries(left, right)
  if left.value == right.value then return left.label < right.label end
  return left.value > right.value
end

local mitigationDetails = {
  { key = "blocked", label = "Blocked" },
  { key = "absorbed", label = "Absorbed" },
  { key = "resisted", label = "Resisted" },
  { key = "glancing", label = "Glancing blows", countOnly = true },
  { key = "crushing", label = "Crushing blows", countOnly = true },
}

local function clearEntry(entry)
  entry.label = nil
  entry.text = nil
  entry.value = nil
  entry.class = nil
  entry.actor = nil
  entry.spell = nil
  entry.threatRow = nil
  entry.modeKey = nil
  entry.segment = nil
  entry.set = nil
  entry.hideRank = nil
  entry.rank = nil
  entry.r = nil
  entry.g = nil
  entry.b = nil
end

function Presenter:GetEntry(index)
  local entry = self.entryPool[index]
  if not entry then
    entry = {}
    self.entryPool[index] = entry
  end
  clearEntry(entry)
  return entry
end

function Presenter:ClearDisplay()
  local i
  for i = 1, table_getn(self.display) do self.display[i] = nil end
end

function Presenter:FormatThreatText(threatRow)
  return (threatRow.estimated and "~" or "") .. Skada:FormatNumber(threatRow.threat) .. " (" ..
    tostring(floor((threatRow.percent or 0) + 0.5)) .. "%) | " ..
    Skada:FormatNumber(threatRow.tps or 0) .. " TPS"
end

function Presenter:BuildThreatDisplay()
  local rows = Skada.Threat and Skada.Threat.rows
  if not rows then return 0 end
  local rowCount = table_getn(rows)
  local visible = self.db and getVisibleRowCount(self.db) or rowCount
  if visible > rowCount then visible = rowCount end

  local playerName = UnitName and UnitName("player") or nil
  local playerIndex, i
  if playerName then
    for i = 1, rowCount do
      if rows[i].name == playerName then playerIndex = i break end
    end
  end

  local displayIndex, sourceIndex, threatRow, entry
  for displayIndex = 1, visible do
    sourceIndex = displayIndex
    if playerIndex and playerIndex > visible and displayIndex == visible then sourceIndex = playerIndex end
    threatRow = rows[sourceIndex]
    entry = self:GetEntry(displayIndex)
    entry.label = threatRow.name
    entry.value = max(0, threatRow.threat or 0)
    entry.rank = sourceIndex
    entry.text = Presenter:FormatThreatText(threatRow)
    entry.class = threatRow.class
    entry.threatRow = threatRow
    self.display[displayIndex] = entry
  end
  return visible
end

function Presenter:BuildModeDisplay(set, mode)
  local count = 0
  local detailActor = self.detailActor and set.actors[self.detailActor]

  if self.detailActor and not detailActor then self.detailActor = nil end
  if detailActor and mode.detail then
    local _, spell, entry
    local spells = detailActor[mode.detail]
    if spells then
      for _, spell in pairs(spells) do
        local value = Skada.Modes:GetDetailValue(mode, spell)
        if value > 0 then
          count = count + 1
          entry = self:GetEntry(count)
          entry.label = spell.name
          entry.value = value
          entry.class = detailActor.class
          entry.actor = detailActor
          entry.spell = spell
          self.display[count] = entry
        end
      end
    end
  else
    local i, actor, value, entry
    for i = 1, table_getn(set.actorList) do
      actor = set.actorList[i]
      value = Skada.Modes:GetActorValue(mode, actor)
      if value > 0 then
        count = count + 1
        entry = self:GetEntry(count)
        entry.label = actor.name
        entry.value = value
        entry.class = actor.class
        entry.actor = actor
        self.display[count] = entry
      end
    end
  end

  table_sort(self.display, sortEntries)
  return count
end

function Presenter:BuildModesDisplay(set)
  local count = 0
  local i, mode, entry
  for i = 1, table_getn(Skada.Modes.list) do
    mode = Skada.Modes.list[i]
    count = count + 1
    entry = self:GetEntry(count)
    entry.label = mode.title
    if mode.live then
      entry.text = Skada.Threat and Skada.Threat:GetSummaryText() or "Unavailable"
    else
      entry.text = Skada.Modes:GetSetTitle(mode, set)
    end
    entry.value = 1
    entry.modeKey = mode.key
    entry.r, entry.g, entry.b = 0.45, 0.48, 0.98
    self.display[count] = entry
  end
  return count
end

function Presenter:FormatDuration(seconds)
  return Common.FormatDuration(seconds)
end

function Presenter:BuildSegmentsDisplay()
  local choices = Skada.Data:GetSegmentChoices(self.segmentChoices)
  local count = table_getn(choices)
  local i, choice, entry, name
  for i = 1, count do
    choice = choices[i]
    entry = self:GetEntry(i)
    name = choice.label
    if choice.value == "current" then
      name = "Current"
    elseif choice.value == "total" then
      name = "Overall"
    elseif type(choice.value) == "number" then
      name = tostring(choice.value) .. ". " .. name
    end
    entry.label = name
    entry.text = self:FormatDuration(Skada.Data:GetSetDuration(choice.set))
    entry.value = 1
    entry.segment = choice.value
    entry.set = choice.set
    entry.hideRank = true
    entry.r, entry.g, entry.b = 0.82, 0.66, 0.30
    self.display[i] = entry
  end
  return count
end

function Presenter:BuildDisplay(set, mode)
  self:ClearDisplay()
  if self.view == "modes" then return self:BuildModesDisplay(set) end
  if self.view == "segments" then return self:BuildSegmentsDisplay() end
  if mode.live then return self:BuildThreatDisplay() end
  return self:BuildModeDisplay(set, mode)
end

function Presenter:GetEntryText(entry)
  if entry.threatRow then
    return Presenter:FormatThreatText(entry.threatRow)
  end
  if entry.spell then
    return Skada.Modes:GetDetailText(self.paintMode, entry.spell, entry.actor, self.paintSet)
  end
  if entry.actor then
    return Skada.Modes:GetActorText(self.paintMode, entry.actor, self.paintSet)
  end
  return entry.text
end

function Presenter:GetTitle(mode)
  if self.view == "modes" then return "Skada: Modes" end
  if self.view == "segments" then return "Skada: Fights" end
  if mode.live then return Skada.Threat and Skada.Threat:GetTitle() or "Threat: Unavailable" end
  if self.detailActor then return self.detailActor .. ": " .. mode.title end
  return mode.title .. ": " .. Skada.Data:GetSegmentLabel(self.db.segment)
end

function Presenter:ShowEntryTooltip(row)
  local entry = row.entry
  if not entry then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  GameTooltip:AddLine(entry.label, 1, 1, 1)
  if rawget(row, "skadaPinned") then
    GameTooltip:AddLine("Pinned while scrolling below your rank.", 0.62, 0.68, 0.76, true)
  end

  if entry.modeKey then
    GameTooltip:AddLine("Click to show this mode.", 0.8, 0.8, 0.8)
  elseif entry.segment ~= nil then
    GameTooltip:AddLine("Click to choose this fight.", 0.8, 0.8, 0.8)
  elseif entry.threatRow then
    local threatRow = entry.threatRow
    local threatLabel = threatRow.estimated and "Estimated threat" or "Server threat"
    GameTooltip:AddDoubleLine(threatLabel, tostring(threatRow.threat or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Aggro", tostring(floor((threatRow.percent or 0) + 0.5)) .. "%", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("TPS", Skada:FormatNumber(threatRow.tps or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Source", threatRow.estimated and "Local estimate" or "OctoWoW server", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Status", threatRow.tank and "Tanking" or "Not tanking", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Range", threatRow.melee and "Melee" or "Ranged", 0.8, 0.8, 0.8, 1, 1, 1)
  elseif entry.spell then
    local spell = entry.spell
    if spell.customText then
      GameTooltip:AddLine(spell.customText, 0.85, 0.85, 0.85, true)
    else
      if spell.effectiveHealing ~= nil then
        local total = spell.amount or 0
        local effective = spell.effectiveHealing or 0
        local overhealing = spell.overhealing or 0
        local efficiency = total > 0 and effective / total * 100 or 0
        GameTooltip:AddDoubleLine("Effective (estimated)", Skada:FormatNumber(effective), 0.8, 0.8, 0.8, 0.3, 1, 0.45)
        GameTooltip:AddDoubleLine("Overheal (estimated)", Skada:FormatNumber(overhealing) .. string.format(" (%.1f%%)", 100 - efficiency), 0.8, 0.8, 0.8, 1, 0.45, 0.35)
        GameTooltip:AddDoubleLine("Total cast healing", Skada:FormatNumber(total), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Efficiency", string.format("%.1f%%", efficiency), 0.8, 0.8, 0.8, 1, 1, 1)
        if spell.unverifiedHealing and spell.unverifiedHealing > 0 then
          GameTooltip:AddDoubleLine("No health snapshot", Skada:FormatNumber(spell.unverifiedHealing), 0.8, 0.8, 0.8, 1, 0.82, 0.3)
        end
      else
        GameTooltip:AddDoubleLine("Total", Skada:FormatNumber(spell.amount or 0), 0.8, 0.8, 0.8, 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("Events", tostring(spell.count or 0), 0.8, 0.8, 0.8, 1, 1, 1)
      if spell.minimum then GameTooltip:AddDoubleLine("Min / Max", Skada:FormatNumber(spell.minimum) .. " / " .. Skada:FormatNumber(spell.maximum), 0.8, 0.8, 0.8, 1, 1, 1) end
      if spell.critical and spell.critical > 0 then
        local criticalPercent = spell.count and spell.count > 0 and spell.critical / spell.count * 100 or 0
        GameTooltip:AddDoubleLine("Critical", tostring(spell.critical) .. string.format(" (%.1f%%)", criticalPercent), 0.8, 0.8, 0.8, 1, 1, 1)
      end
      if spell.duration then GameTooltip:AddDoubleLine("Observed duration", string.format("%.1fs", spell.duration), 0.8, 0.8, 0.8, 1, 1, 1) end
      if spell.powerType then GameTooltip:AddDoubleLine("Resource", spell.powerType, 0.8, 0.8, 0.8, 1, 1, 1) end
    end
  elseif entry.actor then
    local actor = entry.actor
    GameTooltip:AddDoubleLine("Active time", string.format("%.1fs", actor.activeTime or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Damage", Skada:FormatNumber(actor.damage), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Effective healing (estimated)", Skada:FormatNumber(actor.effectiveHealing or actor.healing), 0.8, 0.8, 0.8, 0.3, 1, 0.45)
    GameTooltip:AddDoubleLine("Overhealing (estimated)", Skada:FormatNumber(actor.overhealing or 0), 0.8, 0.8, 0.8, 1, 0.45, 0.35)
    GameTooltip:AddDoubleLine("Total cast healing", Skada:FormatNumber(actor.healing), 0.8, 0.8, 0.8, 1, 1, 1)
    if actor.unverifiedHealing and actor.unverifiedHealing > 0 then
      GameTooltip:AddDoubleLine("No health snapshot", Skada:FormatNumber(actor.unverifiedHealing), 0.8, 0.8, 0.8, 1, 0.82, 0.3)
    end
    GameTooltip:AddDoubleLine("Damage taken", Skada:FormatNumber(actor.damageTaken), 0.8, 0.8, 0.8, 1, 1, 1)
    local hits, misses = actor.hits or 0, actor.misses or 0
    if hits + misses > 0 then
      GameTooltip:AddDoubleLine("Attacks avoided by target",
        tostring(misses) .. string.format(" (%.0f%%)", misses / (hits + misses) * 100), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if actor.mitigated and actor.mitigated > 0 then
      GameTooltip:AddDoubleLine("Outgoing damage mitigated", Skada:FormatNumber(actor.mitigated), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local mitigation = actor.mitigation
    if mitigation then
      local mitigationIndex, detail, observation, mitigationText
      for mitigationIndex = 1, table_getn(mitigationDetails) do
        detail = mitigationDetails[mitigationIndex]
        observation = mitigation[detail.key]
        if observation then
          mitigationText = tostring(observation.count or 0)
          if not detail.countOnly then
            mitigationText = Skada:FormatNumber(observation.amount or 0) .. " (" .. mitigationText .. ")"
          end
          GameTooltip:AddDoubleLine(detail.label, mitigationText, 0.8, 0.8, 0.8, 1, 1, 1)
        end
      end
    end
    if actor.avoids and actor.avoids > 0 then
      GameTooltip:AddDoubleLine("Attacks avoided (dodge/parry/resist)", tostring(actor.avoids), 0.8, 0.8, 0.8, 1, 1, 1)
    end
  end
  GameTooltip:AddLine("Right-click to go back.", 0.55, 0.8, 1)
  GameTooltip:Show()
end
