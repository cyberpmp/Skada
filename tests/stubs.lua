-- WoW API stubs executed before the addon loads. Verbatim port of the former
-- STUBS block in tests/run_tests.py; harness.py executes this before Skada.toc.

table.getn = table.getn or function(value) return #value end
table.wipe = table.wipe or function(value) for key in pairs(value) do value[key] = nil end end

TestDropdownInfos = {}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info, level)
  TestDropdownInfos[table.getn(TestDropdownInfos) + 1] = info
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

function UnitExists(unit) return units[unit] ~= nil end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitClass(unit)
  local value = units[unit]
  return value and value.class, value and value.class
end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitHealth(unit) return units[unit] and units[unit].health or 0 end
function UnitHealthMax(unit) return units[unit] and units[unit].maxHealth or 0 end
function TestSetUnitHealth(unit, health, maximum)
  units[unit].health, units[unit].maxHealth = health, maximum
end
function UnitIsFriend(_, unit) return units[unit] and units[unit].friend end
function UnitIsPlayer(unit) return unit == "player" or unit == "party1" end
function UnitIsDead() return false end
function UnitAffectingCombat() return inCombat end
function UnitSpellTargetName() return UnitName("target") end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 1 end
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

local objectMethods = {}
local function noop() end
local function newObject()
  return setmetatable({}, {
    __index = function(_, key) return objectMethods[key] or noop end,
  })
end
function objectMethods:RegisterEvent() end
function objectMethods:SetScript(name, func)
  if name == "OnClick" and self.frameType ~= "Button" then
    error((self.name or "<unnamed>") .. ' doesn\'t have a "OnClick" script')
  end
  self[name] = func
end
function objectMethods:CreateTexture() return newObject() end
function objectMethods:GetNormalTexture() return newObject() end
function objectMethods:GetPushedTexture() return newObject() end
function objectMethods:CreateFontString() return newObject() end
function objectMethods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function objectMethods:SetPoint(point, relativeTo, relativePoint, x, y)
  self.lastPoint, self.lastRelativeTo, self.lastRelativePoint = point, relativeTo, relativePoint
  self.lastPointX, self.lastPointY = x, y
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
function objectMethods:SetTextColor(r, g, b, a)
  self.textR, self.textG, self.textB, self.textA = r, g, b, a
end
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
function objectMethods:Show() self.shown = true end
function objectMethods:Hide() self.shown = false end
function objectMethods:IsShown() return self.shown ~= false end
function CreateFrame(frameType, name)
  local frame = newObject()
  frame.frameType = frameType
  frame.name = name
  return frame
end
UIParent = newObject()
Minimap = newObject()
GameTooltip = newObject()

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