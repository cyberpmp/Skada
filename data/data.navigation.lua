local Skada = (_G or getfenv(0)).Skada

local DataNavigation = {}
Skada.DataNavigation = DataNavigation

local Common = Skada.Common
local wipeTable = Common.Wipe

local type = type
local tostring = tostring
local table_getn = table.getn
local table_insert = table.insert

local function setSegmentChoice(target, index, value, label, segment)
  local choice = target[index]
  if not choice then
    choice = {}
    target[index] = choice
  end
  choice.value = value
  choice.label = label
  choice.set = segment
end

function DataNavigation:GetSegmentLabel(selection)
  selection = selection or Skada.db.profile.segment
  if selection == "total" then return "Overall" end
  if type(selection) == "number" then
    local set = self.history[selection]
    local name = set and set.name
    if not name or name == "Current" then name = "Fight" end
    return tostring(selection) .. ". " .. name
  end
  return "Current"
end

function DataNavigation:GetSegmentChoices(target)
  target = target or {}
  local previousCount = table_getn(target)

  setSegmentChoice(target, 1, "current", "Current", self.current)
  setSegmentChoice(target, 2, "total", "Overall", self.total)

  local historyIndex, segment
  local choiceCount = 2
  for historyIndex = 1, table_getn(self.history) do
    segment = self.history[historyIndex]
    choiceCount = choiceCount + 1
    setSegmentChoice(target, choiceCount, historyIndex,
      (segment.name and segment.name ~= "Current") and segment.name or "Fight", segment)
  end
  for historyIndex = choiceCount + 1, previousCount do target[historyIndex] = nil end
  return target
end

function DataNavigation:CycleSegment(direction, window)
  if window and Skada.Modes and Skada.Modes:Get(window.db.mode).live then
    window.db.segment = "current"
    if Skada.UI and Skada.UI.SyncLegacy then Skada.UI:SyncLegacy(window) end
    Skada:MarkDirty()
    return
  end
  local entries = self:GetSegmentChoices(self.cycleChoices or {})
  self.cycleChoices = entries
  local choices = self.cycleValues or {}
  self.cycleValues = choices
  wipeTable(choices)
  local entryIndex
  for entryIndex = 1, table_getn(entries) do table_insert(choices, entries[entryIndex].value) end
  local config = window and window.db or Skada.db.profile
  local currentIndex = 1
  local choiceIndex
  for choiceIndex = 1, table_getn(choices) do
    if choices[choiceIndex] == config.segment then currentIndex = choiceIndex break end
  end
  currentIndex = currentIndex + (direction or 1)
  if currentIndex > table_getn(choices) then currentIndex = 1 end
  if currentIndex < 1 then currentIndex = table_getn(choices) end
  config.segment = choices[currentIndex]
  if window then
    window.detailActor = nil
    window.view = "mode"
    window.scrollOffset = 0
    if Skada.UI and Skada.UI.SyncLegacy then Skada.UI:SyncLegacy(window) end
  end
  Skada:MarkDirty()
end

function DataNavigation:OnModeChanged(window)
  if not window then return end
  window.detailActor = nil
  window.view = "mode"
  window.scrollOffset = 0
  if Skada.UI and Skada.UI.SyncLegacy then Skada.UI:SyncLegacy(window) end
end

Skada:Subscribe("segmentArchived", function(data)
  local windows = Skada.db.profile.windows
  local windowIndex, selectedSegment
  if windows and table_getn(windows) > 0 then
    for windowIndex = 1, table_getn(windows) do
      selectedSegment = windows[windowIndex].segment
      if type(selectedSegment) == "number" then windows[windowIndex].segment = selectedSegment + 1 end
    end
  else
    selectedSegment = Skada.db.profile.segment
    if type(selectedSegment) == "number" then Skada.db.profile.segment = selectedSegment + 1 end
  end
  if windows and table_getn(windows) > 0 then
    for windowIndex = 1, table_getn(windows) do
      selectedSegment = windows[windowIndex].segment
      if type(selectedSegment) == "number" and not data.history[selectedSegment] then
        windows[windowIndex].segment = "current"
      end
    end
    Skada.db.profile.segment = windows[1].segment
  elseif type(Skada.db.profile.segment) == "number" and
      not data.history[Skada.db.profile.segment] then
      Skada.db.profile.segment = "current"
  end
end)
