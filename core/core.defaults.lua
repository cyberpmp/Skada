local Skada = (_G or getfenv(0)).Skada

local Defaults = {}
Skada.Defaults = Defaults

-- Profile-wide settings. Everything a meter window owns lives on that
-- window (profile.windows[n]) and defaults from Defaults.window below; the
-- profile keeps no copy of any window's settings.
Defaults.schema = {
  profile = {
    mergePets = true,
    trackAll = false,
    useNampower = true,
    maxSegments = 10,
    onlyBossFights = false,
    autoLog = false,
    resetOnEnterInstance = "ask",
    resetOnJoinGroup = "ask",
    resetOnLeaveGroup = "ask",
    numberFormat = "compact",
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
    windowBorderStyle = "solid",
    windowBorderColor = { 0.10, 0.11, 0.14 },
    minimap = { show = true, angle = 205 },
    windows = {},
    selectedWindowID = 1,
  },
}

-- One meter window's own settings, for a window that has never stored
-- them (the first window of a fresh profile). A window created later
-- copies the active window's values instead (WindowConfig.ApplyDefaults).
Defaults.window = {
  visible = true,
  locked = false,
  width = 240,
  rows = 10,
  barHeight = 18,
  barSpacing = 2,
  fontSize = 15,
  barAlpha = 0.90,
  windowOpacity = 0.90,
  mode = "damage",
  segment = "current",
  point = "CENTER",
  relativePoint = "CENTER",
  x = 320,
  y = 40,
  autoSwitch = true,
  snap = true,
  snapDistance = 12,
  snapGap = 0,
  snapSize = true,
  hideTitle = false,
  combatMode = "",
  nameIsCustom = false,
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
