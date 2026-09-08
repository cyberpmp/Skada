
-- Real WoW exposes the classic strXXX globals natively (find/lower/upper/
-- sub/rep/len have existed since Vanilla). Everything else this client
-- doesn't provide — string.split/trim, loadstring, unpack, floor/ceil/max/min
-- as bare globals, hooksecurefunc, wipe, and (critically) self-healing
-- table.getn/setn/insert/remove that don't go stale against native-style
-- `t[#t+1] = v` appends — comes from core/core.compat.lua, loaded here in
-- its .toc position as on the real client; see load_addon() below.
-- Duplicating those fallbacks here would test the duplicate, not the real
-- shim. Lupa's Lua 5.5 has no table.getn/setn at all (removed after 5.1), so
-- nothing between this stub and core.compat.lua's load may call them directly
-- at top level — lazy (inside a function body) is fine.
strfind = string.find
strlower = string.lower
strupper = string.upper
strsub = string.sub
strrep = string.rep
strlen = string.len

TestDropdownInfos = {}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info, level)
  table.insert(TestDropdownInfos, info)
end
function UIDropDownMenu_Initialize(frame, fn) frame.initialize = fn end
function ToggleDropDownMenu() end
function CloseDropDownMenus() end

TestLastPopup = nil
StaticPopupDialogs = {}
function StaticPopup_Show(key)
  TestLastPopup = key
  return { which = key }
end

YOU = "You"
UNKNOWN = "Unknown"

local clock = 100
local inCombat = false
function TestSetTime(value) clock = value end
function TestSetCombat(value) inCombat = value and true or false end
function GetTime() return clock end

local units = {
  player = { name = "Alice", class = "MAGE", guid = "0xA", friend = true, health = 1000, maxHealth = 1000 },
  pet = { name = "Wolf", class = "WARRIOR", guid = "0xP", friend = true, health = 1000, maxHealth = 1000 },
  party1 = { name = "Bob", class = "PRIEST", guid = "0xB", friend = true, health = 1000, maxHealth = 1000 },
  target = { name = "Boar", class = "WARRIOR", guid = "0xC", friend = false },
}
function TestSetTarget(name, guid)
  units.target.name, units.target.guid = name, guid
end

-- The OctoWoW client resolves a raw GUID string wherever a unit token is
-- accepted (the SuperWoW extension Skada's Nampower ingest depends on), so the
-- stub answers GUID lookups the same way the client does. Units that never sit
-- on a token still resolve once registered here.
local unitsByGUID = {}
local function indexUnitsByGUID()
  local token, value
  for token, value in pairs(units) do
    if value.guid then unitsByGUID[value.guid] = value end
  end
end
indexUnitsByGUID()

function TestRegisterGUIDUnit(guid, name, class, friend, health, maximum)
  unitsByGUID[guid] = {
    name = name, class = class or "WARRIOR", guid = guid,
    friend = friend and true or false,
    health = health or 1000, maxHealth = maximum or 1000,
  }
end

local function resolveUnit(unit)
  indexUnitsByGUID()
  return units[unit] or unitsByGUID[unit]
end

function UnitExists(unit) return resolveUnit(unit) ~= nil end
function UnitName(unit)
  local value = resolveUnit(unit)
  return value and value.name
end
function UnitClass(unit)
  local value = resolveUnit(unit)
  return value and value.class, value and value.class
end
function UnitGUID(unit)
  local value = resolveUnit(unit)
  return value and value.guid
end
function UnitHealth(unit)
  local value = resolveUnit(unit)
  return value and value.health or 0
end
function UnitHealthMax(unit)
  local value = resolveUnit(unit)
  return value and value.maxHealth or 0
end
function TestSetUnitHealth(unit, health, maximum)
  local value = resolveUnit(unit)
  value.health, value.maxHealth = health, maximum
end

-- Nampower's Lua surface. Present by default so the ingest module activates
-- under test; TestSetNampowerPresent(false) exercises the chat-text fallback.
local nampowerPresent = true
local spellNames = {
  [116] = "Frostbolt", [133] = "Fireball", [2050] = "Lesser Heal",
  [8092] = "Mind Blast", [5782] = "Fear", [527] = "Dispel Magic",
}
function TestSetNampowerPresent(value)
  nampowerPresent = value and true or false
  if nampowerPresent then
    GetNampowerVersion = function() return "4.5.0" end
    GetSpellNameAndRankForId = function(spellID) return spellNames[spellID], "Rank 1" end
  else
    GetNampowerVersion = nil
    GetSpellNameAndRankForId = nil
  end
end
TestSetNampowerPresent(true)

TestLastCVars = {}
function SetCVar(name, value) TestLastCVars[name] = value end
function GetCVar(name) return TestLastCVars[name] end
function UnitIsFriend(_, unit) return units[unit] and units[unit].friend end
function UnitIsPlayer(unit) return unit == "player" or unit == "party1" end
function UnitIsDead() return false end
function UnitAffectingCombat() return inCombat end
function UnitSpellTargetName() return UnitName("target") end
function GetNumRaidMembers() return 0 end
local partyMemberCount = 1
function TestSetPartyMembers(value) partyMemberCount = value end
function GetNumPartyMembers() return partyMemberCount end
function GetAddOnMetadata(addonName, field)
  if addonName == "Skada" and field == "Version" then return "1.0.0" end
end
function LoggingCombat() end
function SendAddonMessage(prefix, message, channel)
  TestAddonPrefix, TestAddonMessage, TestAddonChannel = prefix, message, channel
end

C_EventUtils = { IsEventValid = function() return true end }
C_CreatureInfo = {}
C_Spell = {
  GetSpellMechanicByID = function() return 0 end,
  GetSpellEffectMechanics = function() return { 0, 0, 0 } end,
}

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function IsShiftKeyDown() return false end
-- FrameXML helper AceGUI's CheckBox (BigDebuffs' copy) calls to grey out a
-- disabled box; without it a disabled checkbox stops that pane's build.
function SetDesaturation(texture, desaturated)
  if texture and texture.SetDesaturated then texture:SetDesaturated(desaturated) end
end

local objectMethods = {}
local function noop() end
-- Blizzard API methods are always PascalCase; plain data fields an addon (or
-- a vendored library) stashes on a frame are always lowercase-first. Only
-- fall back to a callable noop for the former (an unstubbed API method a
-- test doesn't care about the return value of); an unset lowercase field
-- must read back as real nil, or the extremely common `self.field =
-- self.field or {}` lazy-init idiom silently "initializes" to the noop
-- function instead of a table (see memory: smoke-stub-noop-masking).
local function newObject()
  return setmetatable({}, {
    __index = function(_, key)
      local method = objectMethods[key]
      if method then return method end
      if type(key) == "string" and key:match("^%u") then return noop end
      return nil
    end,
  })
end
function objectMethods:RegisterEvent() end
function objectMethods:SetScript(name, func)
  -- CreateFrame's type argument is case-insensitive on the client (AceGUI —
  -- BigDebuffs' copy — asks for "BUTTON" in places), so compare it that way.
  if name == "OnClick" and string.lower(self.frameType or "") ~= "button" then
    error((self.name or "<unnamed>") .. ' doesn\'t have a "OnClick" script')
  end
  self[name] = func
end
function objectMethods:HookScript(name, func)
  local previous = rawget(self, name)
  self[name] = function(...)
    if previous then previous(...) end
    return func(...)
  end
end
function objectMethods:CreateTexture() return newObject() end
function objectMethods:GetNormalTexture() return newObject() end
function objectMethods:GetPushedTexture() return newObject() end
function objectMethods:CreateFontString() return newObject() end
function objectMethods:GetFontString()
  local fontString = rawget(self, "stubFontString")
  if not fontString then
    fontString = newObject()
    rawset(self, "stubFontString", fontString)
  end
  return fontString
end
function objectMethods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function objectMethods:SetPoint(point, relativeTo, relativePoint, x, y)
  self.lastPoint, self.lastRelativeTo, self.lastRelativePoint = point, relativeTo, relativePoint
  self.lastPointX, self.lastPointY = x, y
end
-- Parenting and layering, modelled on the OctoWoW client as observed in
-- game (see core/core.compat.lua's SetParent shim): a frame takes its
-- parent's strata and parent level + 1 when CREATED, and SetParent moves it
-- without re-deriving either -- so an AceGUI widget built under UIParent and
-- handed to a container inside the settings dialog keeps MEDIUM / level 2
-- unless the shim fixes it. Faking modern inheritance here would hide the
-- exact bug that shim exists for.
local function attachToParent(frame, parent)
  rawset(frame, "stubParent", parent)
  if type(parent) ~= "table" then return end
  local siblings = rawget(parent, "stubChildren")
  if not siblings then
    siblings = {}
    rawset(parent, "stubChildren", siblings)
  end
  siblings[#siblings + 1] = frame
end
local function detachFromParent(frame)
  local parent = rawget(frame, "stubParent")
  local siblings = type(parent) == "table" and rawget(parent, "stubChildren")
  if siblings then
    local kept, siblingIndex = {}, nil
    for siblingIndex = 1, #siblings do
      if siblings[siblingIndex] ~= frame then kept[#kept + 1] = siblings[siblingIndex] end
    end
    rawset(parent, "stubChildren", kept)
  end
  rawset(frame, "stubParent", nil)
end
function objectMethods:GetParent() return rawget(self, "stubParent") end
function objectMethods:SetParent(parent)
  detachFromParent(self)
  attachToParent(self, parent)
end
function objectMethods:GetChildren()
  return (table.unpack or unpack)(rawget(self, "stubChildren") or {})
end
function objectMethods:GetFrameStrata() return rawget(self, "stubStrata") or "MEDIUM" end
function objectMethods:SetFrameStrata(value) rawset(self, "stubStrata", value) end
function objectMethods:SetToplevel(value) rawset(self, "stubToplevel", value and true or false) end
function objectMethods:GetScript(name) return rawget(self, name) end
function objectMethods:SetNormalTexture(value) rawset(self, "normalTexture", value) end
function objectMethods:SetPushedTexture(value) rawset(self, "pushedTexture", value) end
function objectMethods:EnableMouse(value) rawset(self, "stubMouse", value and true or false) end
function objectMethods:IsMouseEnabled() return rawget(self, "stubMouse") end
function objectMethods:SetMinResize(width, height)
  rawset(self, "stubMinWidth", width)
  rawset(self, "stubMinHeight", height)
end
function objectMethods:GetLeft() return rawget(self, "left") end
function objectMethods:GetTop() return rawget(self, "top") end
function objectMethods:GetFrameLevel() return rawget(self, "frameLevel") or 1 end
function objectMethods:SetFrameLevel(value) rawset(self, "frameLevel", value) end
function objectMethods:SetWidth(value) rawset(self, "width", value) end
function objectMethods:SetHeight(value) rawset(self, "height", value) end
function objectMethods:GetWidth() return rawget(self, "width") or 240 end
function objectMethods:GetHeight() return rawget(self, "height") or 208 end
function objectMethods:SetHitRectInsets(left, right, top, bottom)
  self.hitLeft, self.hitRight, self.hitTop, self.hitBottom = left, right, top, bottom
end
function objectMethods:SetText(value) self.textValue = value end
function objectMethods:GetText() return rawget(self, "textValue") end
function objectMethods:GetEffectiveScale() return rawget(self, "stubScale") or 1 end
function objectMethods:SetTextColor(r, g, b, a)
  self.textR, self.textG, self.textB, self.textA = r, g, b, a
end
function objectMethods:SetBackdrop(value) self.backdrop = value end
function objectMethods:SetBackdropColor(r, g, b, a)
  self.backdropR, self.backdropG, self.backdropB, self.backdropA = r, g, b, a
end
function objectMethods:SetBackdropBorderColor(r, g, b, a)
  self.borderR, self.borderG, self.borderB, self.borderA = r, g, b, a
end
function objectMethods:SetTexture(value) rawset(self, "texture", value) end
function objectMethods:SetDesaturated(value) self.desaturated = value and true or false end
function objectMethods:SetVertexColor(r, g, b, a)
  self.vertexR, self.vertexG, self.vertexB, self.vertexA = r, g, b, a
end
function objectMethods:GetStringWidth() return rawget(self, "textValue") and #tostring(rawget(self, "textValue")) * 7 or 0 end
function objectMethods:SetFont(path, size, flags)
  self.fontPath, self.fontSize, self.fontFlags = path, size, flags
end
function objectMethods:SetAlpha(value) self.alpha = value end
function objectMethods:Show()
  local wasShown = self.shown ~= false
  self.shown = true
  local onShow = rawget(self, "OnShow")
  if onShow and not wasShown then onShow(self) end
end
function objectMethods:Hide()
  local wasShown = self.shown ~= false
  self.shown = false
  local onHide = rawget(self, "OnHide")
  if onHide and wasShown then onHide(self) end
end
function objectMethods:IsShown() return self.shown ~= false end
function objectMethods:SetFocus() rawset(self, "stubFocused", true) end
function objectMethods:ClearFocus() rawset(self, "stubFocused", false) end
function objectMethods:GetName() return rawget(self, "name") end

-- Slider frames. The real client fires OnValueChanged for EVERY SetValue,
-- programmatic ones included, so callers that must not loop wrap their
-- SetValue in a `setup` re-entrancy flag (the vendored AceGUI Slider
-- widget's pattern, kept for Skada's own sliders); the stub reproduces that
-- contract, skipping the script only while the flag is set.
function objectMethods:SetMinMaxValues(minValue, maxValue)
  rawset(self, "stubMinValue", minValue)
  rawset(self, "stubMaxValue", maxValue)
end
function objectMethods:GetMinMaxValues()
  return rawget(self, "stubMinValue") or 0, rawget(self, "stubMaxValue") or 0
end
function objectMethods:SetValueStep(valueStep) rawset(self, "stubValueStep", valueStep) end
function objectMethods:GetValueStep() return rawget(self, "stubValueStep") or 1 end
function objectMethods:GetValue() return rawget(self, "stubValue") or 0 end
function objectMethods:SetValue(value)
  rawset(self, "stubValue", value)
  if rawget(self, "setup") then return end
  local onValueChanged = rawget(self, "OnValueChanged")
  if onValueChanged then onValueChanged(self, value) end
end
function objectMethods:SetOrientation(orientation) rawset(self, "stubOrientation", orientation) end
function objectMethods:GetOrientation() return rawget(self, "stubOrientation") end
function objectMethods:SetThumbTexture(value) rawset(self, "thumbTexture", value) end
function objectMethods:GetThumbTexture() return rawget(self, "thumbTexture") end
function objectMethods:EnableMouseWheel(value) rawset(self, "stubMouseWheel", value and true or false) end
function objectMethods:IsMouseWheelEnabled() return rawget(self, "stubMouseWheel") end

-- Blizzard's color picker API (frame methods on the shared ColorPickerFrame;
-- Skada's color control and AceGUI's ColorPicker widget both call these).
function objectMethods:SetColorRGB(colorR, colorG, colorB)
  rawset(self, "stubColorR", colorR)
  rawset(self, "stubColorG", colorG)
  rawset(self, "stubColorB", colorB)
end
function objectMethods:GetColorRGB()
  return rawget(self, "stubColorR") or 0, rawget(self, "stubColorG") or 0,
    rawget(self, "stubColorB") or 0
end

-- Vanilla's Blizzard XML templates pre-populate named child widgets as
-- globals named "<frameName><Suffix>" when instantiated for real; stub that
-- for the Vanilla templates Skada's settings dialog instantiates (the pane
-- scroll frame in options/options.dialog.lua).
-- OptionsListButtonTemplate (TreeGroup's sidebar rows, built by BigDebuffs'
-- Ace3 copy) is deliberately NOT stubbed: the real client has no such
-- template and hands back a bare Button, and core/core.compat.lua's
-- CreateFrame wrapper rebuilds its size, highlight, `.toggle` and `.text` --
-- faking them here would test the fake instead of that shim.
local TEMPLATE_GLOBAL_CHILDREN = {
  UIDropDownMenuTemplate = { "Left", "Middle", "Right", "Button", "Text" },
  UIPanelScrollFrameTemplate = { "ScrollBar" },
}

local function newFrame(frameType, name, parent)
  local frame = newObject()
  frame.frameType = frameType
  frame.name = name
  attachToParent(frame, parent)
  if type(parent) == "table" then
    rawset(frame, "stubStrata", parent:GetFrameStrata())
    rawset(frame, "frameLevel", parent:GetFrameLevel() + 1)
  end
  return frame
end

function CreateFrame(frameType, name, parent, template)
  local frame = newFrame(frameType, name, parent)
  if template and name and TEMPLATE_GLOBAL_CHILDREN[template] then
    -- Template children are real child frames of the new frame (they share
    -- its layering); the dropdown's "$parentButton" is a Button, which is
    -- the only child type the client lets carry an OnClick script.
    local suffixIndex, suffixes, suffix
    suffixes = TEMPLATE_GLOBAL_CHILDREN[template]
    for suffixIndex = 1, #suffixes do
      suffix = suffixes[suffixIndex]
      _G[name .. suffix] = newFrame(suffix == "Button" and "Button" or "Frame", name .. suffix, frame)
    end
  end
  return frame
end
UIParent = newObject()
Minimap = newObject()
GameTooltip = newObject()

-- Blizzard's shared color picker (FrameXML ColorPickerFrame.xml): a hidden,
-- toplevel, DIALOG-strata frame whose Okay/Cancel buttons and opacity slider
-- are child frames that inherited that strata when the XML loaded. Skada's
-- color control (and AceGUI's ColorPicker widget) re-layers the frame and
-- shows it; core/core.compat.lua hooks that show to carry the new layering
-- down to these children.
function objectMethods:IsToplevel() return rawget(self, "stubToplevel") end
ColorPickerFrame = CreateFrame("ColorSelect", "ColorPickerFrame", UIParent)
ColorPickerFrame:SetFrameStrata("DIALOG")
ColorPickerFrame:SetToplevel(true)
ColorPickerFrame.shown = false
ColorPickerOkayButton = CreateFrame("Button", "ColorPickerOkayButton", ColorPickerFrame)
ColorPickerCancelButton = CreateFrame("Button", "ColorPickerCancelButton", ColorPickerFrame)
OpacitySliderFrame = CreateFrame("Slider", "OpacitySliderFrame", ColorPickerFrame)

COMBATHITSELFOTHER = "You hit %s for %d."
COMBATHITOTHEROTHER = "%s hits %s for %d."
SPELLLOGSCHOOLSELFOTHER = "Your %s hits %s for %d %s damage."
SPELLLOGCRITSCHOOLSELFOTHER = "Your %s crits %s for %d %s damage."
HEALEDSELFOTHER = "Your %s heals %s for %d."
HEALEDOTHEROTHER = "%s's %s heals %s for %d."
HEALEDCRITOTHEROTHER = "%s's %s critically heals %s for %d."
PERIODICAURADAMAGESELFOTHER = "%s suffers %d %s damage from your %s."
PERIODICAURAHEALOTHEROTHER = "%s gains %d health from %s's %s."
UNITDIESOTHER = "%s dies."
UNITDIESSELF = "You die."

-- RollFor (enabled on every character of this install, and alphabetically
-- ahead of Skada in load order) overwrites string.match in its
-- srcanillaackport.lua with a captures-only, init-ignoring version;
-- this mirrors that function exactly. Reproducing the clobber here makes
-- core/core.compat.lua's probe-and-replace run the way it does in game:
-- without it the probe takes the "already correct" branch and the repair
-- path — the one Skada's own slash-command parsing depends on — goes
-- untested.
string.match = function(str, pattern)
  if not str then return nil end
  local _, _, capture1, capture2, capture3, capture4, capture5, capture6,
    capture7, capture8, capture9 = string.find(str, pattern)
  return capture1, capture2, capture3, capture4, capture5, capture6, capture7,
    capture8, capture9
end
