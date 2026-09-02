-- Addon chunks on the OctoWoW client receive no varargs and no _G global
-- (ClassicAPI's Compat.lua bootstraps _G from getfenv(0) for the same
-- reason). The chunk environment is the shared global environment, so
-- resolve it directly and store the namespace there. First file in Skada.toc
-- and owns namespace creation.
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

string.gmatch = string.gmatch or string.gfind
string.gfind = string.gfind or string.gmatch

if not string.match then

  local string_find = string.find
  local string_sub = string.sub
  function string.match(s, pattern, init)
    local start, stop, c1, c2, c3, c4, c5 = string_find(s, pattern, init)
    if not start then return nil end
    if c1 == nil then return string_sub(s, start, stop) end
    return c1, c2, c3, c4, c5
  end
end

local string_match = string.match
Common.Match = string_match

function Common.Wipe(tbl)
  if table.wipe then
    table.wipe(tbl)
  else
    local key
    for key in pairs(tbl) do tbl[key] = nil end
  end
  -- Lua 5.0 (the client runtime): table.insert/table.remove maintain an
  -- out-of-band size that table.getn trusts, and wiping the keys does not
  -- reset it -- a wiped list would keep reporting its previous length. The
  -- addon mixes wipes with getn-based iteration, so clear the size too.
  if table.setn then table.setn(tbl, 0) end
end

function Common.Trim(value)
  if type(value) ~= "string" then return value end

  if not string.find(value, "^%s") and not string.find(value, "%s$") then return value end
  return string.gsub(value, "^%s*(.-)%s*$", "%1")
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
