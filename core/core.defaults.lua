local Skada = (_G or getfenv(0)).Skada

local Defaults = {}
Skada.Defaults = Defaults

Defaults.schema = {
  profile = {
    visible = true,
    locked = false,
    width = 240,
    rows = 10,
    barHeight = 18,
    barSpacing = 2,
    fontSize = 15,
    barAlpha = 0.90,
    updateRate = 0.25,
    mode = "damage",
    segment = "current",
    mergePets = true,
    trackAll = false,
    maxSegments = 10,
    onlyBossFights = false,
    autoLog = false,
    resetOnEnterInstance = "ask",
    resetOnJoinGroup = "ask",
    resetOnLeaveGroup = "ask",
    numberFormat = "compact",
    snap = true,
    snapDistance = 12,
    snapGap = 0,
    snapSize = true,
    hideTitle = false,
    combatMode = "",
    returnAfterCombat = false,
    fontName = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf",
    classColors = true,
    barColor = { 0.25, 0.55, 1.0 },
    barTexture = "flat",
    spellColors = true,
    showClassIcons = false,
    classColorMenus = false,
    highlightSelf = false,
    highlightSelfColor = { 1.0, 0.82, 0.0 },
    barBorder = false,
    barBorderColor = { 1.0, 1.0, 1.0 },
    windowOpacity = 0.90,
    windowBorderStyle = "solid",
    windowBorderColor = { 0.10, 0.11, 0.14 },
    -- Kept for saved-variable compatibility; windowBorderStyle supersedes it.
    hideWindowBorder = false,
    smoothBars = true,
    barSpeed = 8,
    minimap = { show = true, angle = 205 },
    windows = {},
    selectedWindowID = 1,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 320,
    y = 40,
  },
}

function Defaults.ApplyDefaults(target, schema)
  local type = type
  local pairs = pairs
  local key, value
  for key, value in pairs(schema) do
    if target[key] == nil then
      if type(value) == "table" then
        target[key] = {}
        Defaults.ApplyDefaults(target[key], value)
      else
        target[key] = value
      end
    elseif type(value) == "table" and type(target[key]) == "table" then
      Defaults.ApplyDefaults(target[key], value)
    end
  end
end
