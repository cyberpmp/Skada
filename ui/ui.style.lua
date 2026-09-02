local Skada = (_G or getfenv(0)).Skada

local Style = {}
Skada.UIStyle = Style

local max = math.max
local min = math.min
local table_getn = table.getn

local MEDIA = "Interface\\AddOns\\Skada\\media\\"

Style.WHITE = "Interface\\Buttons\\WHITE8X8"
Style.FLAT_BAR = MEDIA .. "FlatBar.tga"
Style.CLASS_ICONS = MEDIA .. "classicons.tga"
Style.SHADOW = MEDIA .. "glow2.tga"
Style.MELEE_ICON = "Interface\\Icons\\Ability_MeleeDamage"

Style.HEADER_HEIGHT = 28
Style.HEADER_BUTTON_WIDTH = 18
Style.HEADER_BUTTON_HEIGHT = 18
Style.HEADER_BUTTON_GAP = 2
Style.HEADER_BUTTON_ALPHA = 0.82
Style.MIN_WINDOW_WIDTH = 180
Style.WINDOW_PADDING = 6
Style.FOOTER_HEIGHT = 6

Style.WINDOW_R, Style.WINDOW_G, Style.WINDOW_B = 0.018, 0.021, 0.028
Style.SURFACE_R, Style.SURFACE_G, Style.SURFACE_B = 0.045, 0.050, 0.064
Style.ROW_R, Style.ROW_G, Style.ROW_B = 0.040, 0.044, 0.055
Style.MUTED_R, Style.MUTED_G, Style.MUTED_B = 0.60, 0.63, 0.69
Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B = 0.38, 0.61, 0.80
-- Settings-window palette: pane interiors/borders and the gold accents used
-- by the title medallion, live values, and selected tree rows.
Style.PANE_BG_R, Style.PANE_BG_G, Style.PANE_BG_B, Style.PANE_BG_A = 0.1, 0.1, 0.1, 0.5
Style.PANE_BORDER_R, Style.PANE_BORDER_G, Style.PANE_BORDER_B = 0.4, 0.4, 0.4
Style.GOLD_R, Style.GOLD_G, Style.GOLD_B = 1, 0.82, 0
Style.GOLD_BRIGHT_R, Style.GOLD_BRIGHT_G, Style.GOLD_BRIGHT_B = 1, 0.9, 0.2

Style.FLAT_BACKDROP = {
  bgFile = Style.WHITE,
  edgeFile = Style.WHITE,
  tile = false,
  tileSize = 0,
  edgeSize = 1,
  insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

-- Meter-window border only; the window fill is a dedicated texture so its
-- opacity can ride on SetAlpha (backdrop-color alpha is not reliable on
-- every client, and a near-opaque row background sits on top anyway).
Style.WINDOW_BORDER_BACKDROP = {
  edgeFile = Style.WHITE,
  edgeSize = 1,
  insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

Style.SHADOW_BACKDROP = {
  edgeFile = Style.SHADOW,
  edgeSize = 8,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

Style.WINDOW_BORDER_STYLES = {
  { value = "shadow", label = "Soft shadow (default)" },
  { value = "solid", label = "Solid color" },
  { value = "none", label = "None" },
}

Style.BAR_TEXTURES = {
  { value = "flat", label = "Flat (default)" },
  { value = "banto", label = "Smooth" },
  { value = "elvui", label = "ElvUI" },
  { value = "gradient", label = "Gradient" },
  { value = "striped", label = "Striped" },
  { value = "tukui", label = "TukUI" },
  { value = "blizzard", label = "Blizzard" },
}

Style.SPELL_COLORS = {
  { 0.95, 0.55, 0.15 },
  { 0.35, 0.75, 0.95 },
  { 0.75, 0.35, 0.95 },
  { 0.95, 0.35, 0.55 },
  { 0.45, 0.85, 0.35 },
  { 0.95, 0.85, 0.25 },
  { 0.35, 0.95, 0.85 },
  { 0.85, 0.55, 0.95 },
}

Style.CLASS_ICON_TCOORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 },
  MAGE = { 0.25, 0.49609375, 0, 0.25 },
  ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
  HUNTER = { 0, 0.25, 0.25, 0.5 },
  SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
  WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 },
}

function Style:GetBarTexture()
  local profile = Skada.db and Skada.db.profile
  local key = profile and profile.barTexture or "flat"
  if key == "banto" then return MEDIA .. "BantoBar.tga" end
  if key == "blizzard" then return "Interface\\TargetingFrame\\UI-StatusBar" end
  if key == "elvui" or key == "gradient" or key == "striped" or key == "tukui" then
    return MEDIA .. "bar_" .. key .. ".tga"
  end
  return self.FLAT_BAR
end

function Style:GetSpellColor(index)
  local colors = self.SPELL_COLORS
  local color = colors[((max(1, index or 1) - 1) % table_getn(colors)) + 1]
  return color[1], color[2], color[3]
end

function Style:GetAccentColor()
  local class
  if UnitClass then
    local _, classToken = UnitClass("player")
    class = classToken
  end
  return Skada:GetClassColor(class)
end

function Style:GetBarEase()
  local profile = Skada.db and Skada.db.profile
  if profile and profile.smoothBars == false then return 1 end
  local speed = profile and tonumber(profile.barSpeed) or 8
  speed = min(10, max(1, speed))
  return 0.04 + speed * 0.025
end

function Style:ApplyFlatFrame(frame, alpha, borderR, borderG, borderB)
  frame:SetBackdrop(self.FLAT_BACKDROP)
  frame:SetBackdropColor(self.WINDOW_R, self.WINDOW_G, self.WINDOW_B, alpha or 0.9)
  frame:SetBackdropBorderColor(borderR or 0.10, borderG or 0.11, borderB or 0.14, 1)
end

function Style:ApplyShadow(frame, visible)
  local shadow = rawget(frame, "skadaShadow")
  if visible then
    if not shadow then
      shadow = CreateFrame("Frame", nil, frame)
      shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 5)
      shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
      shadow:SetBackdrop(self.SHADOW_BACKDROP)
      shadow:SetBackdropBorderColor(0, 0, 0, 0.30)
      shadow:SetFrameLevel(max(0, frame:GetFrameLevel() - 1))
      rawset(frame, "skadaShadow", shadow)
    end
    shadow:Show()
  elseif shadow then
    shadow:Hide()
  end
end

-- The window backdrop alone is invisible in practice: every row paints its
-- own dark texture over it, so the opacity setting has to reach that chrome
-- too or the slider appears to do nothing. 0% makes the whole window
-- background disappear and leaves only bars, text, and buttons. Per window.
function Style:GetWindowOpacity(db)
  local opacity = db and db.windowOpacity
  if type(opacity) ~= "number" then return 0.9 end
  return max(0, min(1, opacity))
end

-- The window fill as a plain texture: SetAlpha on it is the one transparency
-- path every client honors, so the opacity slider always has a visible effect.
function Style:ApplyWindowBackground(frame, opacity)
  local bg = rawget(frame, "skadaBg")
  if not bg then
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(self.WHITE)
    bg:SetAllPoints(frame)
    rawset(frame, "skadaBg", bg)
  end
  bg:SetVertexColor(self.WINDOW_R, self.WINDOW_G, self.WINDOW_B)
  bg:SetAlpha(opacity)
  return bg
end

function Style:ApplyMeterWindow(frame, active, opacity)
  local profile = Skada.db.profile
  local borderStyle = profile.hideWindowBorder and "none" or profile.windowBorderStyle or "shadow"
  local hideBorder = borderStyle == "none"
  local color = profile.windowBorderColor or { 0.10, 0.11, 0.14 }
  local borderR, borderG, borderB = color[1] or 0.10, color[2] or 0.11, color[3] or 0.14
  -- Solid is deliberately stable: selecting the window must not replace the
  -- chosen edge color with the active-window highlight.
  if active and borderStyle == "shadow" then
    if profile.classColorMenus then
      borderR, borderG, borderB = self:GetAccentColor()
      borderR, borderG, borderB = borderR * 0.72, borderG * 0.72, borderB * 0.72
    else
      borderR, borderG, borderB = 0.28, 0.32, 0.40
    end
  end
  frame:SetBackdrop(self.WINDOW_BORDER_BACKDROP)
  frame:SetBackdropBorderColor(borderR, borderG, borderB, 1)
  self:ApplyWindowBackground(frame, opacity or 0.9)
  if hideBorder then frame:SetBackdropBorderColor(0, 0, 0, 0) end
  self:ApplyShadow(frame, borderStyle == "shadow")
end

function Style:ApplyHeader(window)
  if not window or not window.headerTexture then return end
  local profile = Skada.db.profile
  local active = window.manager and window.manager.visualActive == window
  local r, g, b = 0.055, 0.060, 0.075
  if active then r, g, b = 0.072, 0.078, 0.098 end
  if profile.classColorMenus then
    local ar, ag, ab = self:GetAccentColor()
    local strength = active and 0.18 or 0.11
    r, g, b = r + ar * strength, g + ag * strength, b + ab * strength
  end
  local opacity = self:GetWindowOpacity(window.db)
  window.headerTexture:SetTexture(self.WHITE)
  -- carry transparency through SetAlpha: some clients ignore the alpha
  -- argument of SetVertexColor, and the dedicated method always works
  window.headerTexture:SetVertexColor(r, g, b)
  window.headerTexture:SetAlpha(0.92 * opacity)
  if window.headerRule then
    local rr, rg, rb = 0.34, 0.38, 0.47
    if active and profile.classColorMenus then rr, rg, rb = self:GetAccentColor() end
    window.headerRule:SetVertexColor(rr, rg, rb)
    window.headerRule:SetAlpha((active and 0.52 or 0.20) * opacity)
  end
  if window.title then
    if active then
      window.title:SetTextColor(0.94, 0.95, 0.98, 1)
    else
      window.title:SetTextColor(0.76, 0.79, 0.84, 1)
    end
  end
end

function Style:ApplyButton(button, hovered)
  if not button then return end
  rawset(button, "skadaHovered", hovered and true or false)
  button:SetBackdrop(self.FLAT_BACKDROP)
  local active = rawget(button, "skadaActive")
  local r, g, b
  if active then
    r, g, b = rawget(button, "skadaActiveR") or 0.20,
      rawget(button, "skadaActiveG") or 1,
      rawget(button, "skadaActiveB") or 0.20
    button:SetBackdropColor(r * 0.11, g * 0.11, b * 0.11, 0.90)
  elseif hovered then
    button:SetBackdropColor(0.14, 0.15, 0.18, 0.94)
  else
    button:SetBackdropColor(0.035, 0.040, 0.052, 0.58)
  end

  if active then
    button:SetBackdropBorderColor(r, g, b, 0.72)
  elseif Skada.db.profile.classColorMenus then
    r, g, b = self:GetAccentColor()
    button:SetBackdropBorderColor(r, g, b, hovered and 0.82 or 0.22)
  elseif hovered then
    button:SetBackdropBorderColor(0.50, 0.55, 0.66, 0.92)
  else
    button:SetBackdropBorderColor(0.20, 0.22, 0.27, 0.52)
  end

  local label = rawget(button, "text")
  if label then
    if active then
      label:SetTextColor(r, g, b, 1)
    elseif hovered then
      label:SetTextColor(1, 1, 1, 1)
    else
      label:SetTextColor(0.82, 0.85, 0.90, 1)
    end
  end
  local symbolH = rawget(button, "symbolH")
  if symbolH then
    local tone = hovered and 1 or 0.84
    symbolH:SetVertexColor(tone, tone, tone, 1)
    local symbolV = rawget(button, "symbolV")
    if symbolV then symbolV:SetVertexColor(tone, tone, tone, 1) end
  end

  local marker = rawget(button, "activeMarker")
  if marker then
    if active then
      marker:SetVertexColor(r, g, b, 1)
      marker:Show()
    else
      marker:Hide()
    end
  end
end

function Style:FadeIn(frame, fromAlpha, duration, targetAlpha)
  if not frame or not frame.SetScript then return end
  rawset(frame, "skadaFadeElapsed", 0)
  rawset(frame, "skadaFadeFrom", fromAlpha or 0.35)
  rawset(frame, "skadaFadeDuration", duration or 0.12)
  rawset(frame, "skadaFadeTarget", targetAlpha or 1)
  frame:SetAlpha(rawget(frame, "skadaFadeFrom"))
  frame:SetScript("OnUpdate", function(self, elapsed)
    elapsed = elapsed or arg1 or 0
    local total = (rawget(self, "skadaFadeElapsed") or 0) + elapsed
    local span = rawget(self, "skadaFadeDuration") or 0.12
    local progress = span > 0 and min(1, total / span) or 1
    local first = rawget(self, "skadaFadeFrom") or 0.35
    local target = rawget(self, "skadaFadeTarget") or 1
    rawset(self, "skadaFadeElapsed", total)
    self:SetAlpha(first + (target - first) * progress)
    if progress >= 1 then self:SetScript("OnUpdate", nil) end
  end)
end

function Style:SetButtonActive(button, active, r, g, b)
  if not button then return end
  rawset(button, "skadaActive", active and true or false)
  rawset(button, "skadaActiveR", r or 0.20)
  rawset(button, "skadaActiveG", g or 1)
  rawset(button, "skadaActiveB", b or 0.20)
  self:ApplyButton(button, rawget(button, "skadaHovered"))
end
