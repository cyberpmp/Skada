local Skada = (_G or getfenv(0)).Skada

local DataNavigation = {}
Skada.DataNavigation = DataNavigation

local type = type
local tostring = tostring
local table_getn = table.getn

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

function DataNavigation:OnModeChanged(window)
  window.detailActor = nil
  window.view = "mode"
  window.scrollOffset = 0
  Skada.UI:NotifyWindowChanged(window)
end

-- A newly archived fight pushes every saved fight one index down: a pinned
-- fight follows its fight, or falls back to Current once trimmed away.
local function followFight(data, segment)
  if type(segment) ~= "number" then return segment end
  return data.history[segment + 1] and segment + 1 or "current"
end

Skada:Subscribe("segmentArchived", function(data)
  local windows = Skada.db.profile.windows
  local windowIndex, config
  for windowIndex = 1, table_getn(windows) do
    config = windows[windowIndex]
    config.segment = followFight(data, config.segment)
    -- The segment a combat mode will hand back follows its fight too.
    config.restoreSegment = followFight(data, config.restoreSegment)
  end
  Skada:Publish("windowSettingsChanged")
end)
