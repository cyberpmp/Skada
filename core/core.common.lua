local env = _G or getfenv(0)
local Skada = env.Skada
if not Skada then
  Skada = {}
  env.Skada = Skada
end

local Common = {}
Skada.Common = Common

local pairs = pairs
local type = type
local string_byte = string.byte
local string_gsub = string.gsub

string.gmatch = string.gmatch or string.gfind
string.gfind = string.gfind or string.gmatch

if not string.match then

  local string_find = string.find
  local string_sub = string.sub
  function string.match(text, pattern, init)
    local start, stop, first, second, third, fourth, fifth = string_find(text, pattern, init)
    if not start then return nil end
    if first == nil then return string_sub(text, start, stop) end
    return first, second, third, fourth, fifth
  end
end

local string_match = string.match
Common.Match = string_match

function Common.Wipe(targetTable)
  if table.wipe then
    table.wipe(targetTable)
  else
    local key
    for key in pairs(targetTable) do targetTable[key] = nil end
  end
  if table.setn then table.setn(targetTable, 0) end
end

function Common.Trim(value)
  if type(value) ~= "string" then return value end

  local first = string_byte(value, 1)
  local last = string_byte(value, -1)
  local firstIsSpace = first == 32 or (first and first >= 9 and first <= 13)
  local lastIsSpace = last == 32 or (last and last >= 9 and last <= 13)
  if not firstIsSpace and not lastIsSpace then return value end
  return string_gsub(value, "^%s*(.-)%s*$", "%1")
end

function Common.GetClickButton(positional)
  if positional then return positional end
  if GetMouseButtonClicked then
    local name = GetMouseButtonClicked()
    if name then return name end
  end
  return arg1
end

function Common.GetWheelDelta(positional)
  if positional then return positional end
  return tonumber(arg1) or 0
end

Common.FONT = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf"

function Common.SetFont(fontString, size)

  local profileFont = Skada.db and Skada.db.profile.fontName
  fontString:SetFont(profileFont or Common.FONT, size, "OUTLINE")
  fontString:SetTextColor(1, 1, 1, 1)
  fontString:SetShadowColor(0, 0, 0, 1)
  fontString:SetShadowOffset(1, -1)
end

Common.BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  tile = false,
  tileSize = 0,
  edgeSize = 1,
  insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

Common.TRACK_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Buttons\\WHITE8X8",
  tile = false,
  tileSize = 0,
  edgeSize = 1,
  insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

function Common.FormatDuration(seconds)
  local floor = math.floor
  seconds = floor((seconds or 0) + 0.5)
  return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local classColors = {
  DRUID = { 1.00, 0.49, 0.04 },
  HUNTER = { 0.67, 0.83, 0.45 },
  MAGE = { 0.41, 0.80, 0.94 },
  PALADIN = { 0.96, 0.55, 0.73 },
  PRIEST = { 1.00, 1.00, 1.00 },
  ROGUE = { 1.00, 0.96, 0.41 },
  SHAMAN = { 0.00, 0.44, 0.87 },
  WARLOCK = { 0.58, 0.51, 0.79 },
  WARRIOR = { 0.78, 0.61, 0.43 },
  OTHER = { 0.65, 0.65, 0.65 },
}

function Common.FormatNumber(value, style)
  local floor = math.floor
  value = tonumber(value) or 0
  if style == "full" then
    return tostring(floor(value + 0.5))
  end
  if style == "compact1" then
    if value >= 1000000 then
      return string.format("%.1fm", value / 1000000)
    elseif value >= 1000 then
      return string.format("%.1fk", value / 1000)
    end
    return tostring(floor(value + 0.5))
  end
  if value >= 1000000 then
    return string.format("%.2fm", value / 1000000)
  elseif value >= 10000 then
    return string.format("%.0fk", value / 1000)
  end
  return tostring(floor(value + 0.5))
end

function Common.GetClassColor(class)
  local color = classColors[class or "OTHER"] or classColors.OTHER
  return color[1], color[2], color[3]
end
