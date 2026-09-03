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
Style.BAR_ANIMATION_SPEED = 5
Style.BAR_EASE = 0.04 + Style.BAR_ANIMATION_SPEED * 0.025

Style.WINDOW_R, Style.WINDOW_G, Style.WINDOW_B = 0.018, 0.021, 0.028
Style.SURFACE_R, Style.SURFACE_G, Style.SURFACE_B = 0.045, 0.050, 0.064
Style.ROW_R, Style.ROW_G, Style.ROW_B = 0.040, 0.044, 0.055
Style.MUTED_R, Style.MUTED_G, Style.MUTED_B = 0.60, 0.63, 0.69
Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B = 0.38, 0.61, 0.80
Style.PANE_BG_R, Style.PANE_BG_G, Style.PANE_BG_B, Style.PANE_BG_A = 0.1, 0.1, 0.1, 0.5
Style.PANE_BORDER_R, Style.PANE_BORDER_G, Style.PANE_BORDER_B = 0.4, 0.4, 0.4
Style.GOLD_R, Style.GOLD_G, Style.GOLD_B = 1, 0.82, 0
Style.GOLD_BRIGHT_R, Style.GOLD_BRIGHT_G, Style.GOLD_BRIGHT_B = 1, 0.9, 0.2

Style.DIALOG_HEADER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

Style.DIALOG_BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

Style.PANE_BACKDROP = {
  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 3, right = 3, top = 5, bottom = 3 },
}

Style.UI_FONT = "Fonts\\FRIZQT__.TTF"
if GameFontNormal and GameFontNormal.GetFont then
  local path = GameFontNormal:GetFont()
  if type(path) == "string" then Style.UI_FONT = path end
end

Style.FLAT_BACKDROP = {
  bgFile = Style.WHITE,
  edgeFile = Style.WHITE,
  tile = false,
  tileSize = 0,
  edgeSize = 1,
  insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

Style.SHADOW_BACKDROP = {
  edgeFile = Style.SHADOW,
  edgeSize = 8,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

Style.WINDOW_BORDER_STYLES = {
  { value = "solid", label = "Solid color (default)" },
  { value = "shadow", label = "Soft shadow" },
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

function Style.SetUIFont(fontString, size)
  fontString:SetFont(Style.UI_FONT, size)
end

function Style:ApplyDialogFrame(frame)
  frame:SetBackdrop(self.DIALOG_BACKDROP)
  frame:SetBackdropColor(0, 0, 0, 1)
end

function Style:ApplyPane(frame, alpha)
  frame:SetBackdrop(self.PANE_BACKDROP)
  frame:SetBackdropColor(self.PANE_BG_R, self.PANE_BG_G, self.PANE_BG_B,
    alpha or self.PANE_BG_A)
  frame:SetBackdropBorderColor(self.PANE_BORDER_R, self.PANE_BORDER_G,
    self.PANE_BORDER_B, 1)
end

function Style:CreateDialogTitle(frame, text)
  local titleBackground = frame:CreateTexture(nil, "OVERLAY")
  titleBackground:SetTexture(self.DIALOG_HEADER_TEXTURE)
  titleBackground:SetWidth(100)
  titleBackground:SetHeight(40)
  titleBackground:SetPoint("TOP", frame, "TOP", 0, 12)
  titleBackground:SetTexCoord(0.31, 0.67, 0, 0.63)

  local titleBackgroundLeft = frame:CreateTexture(nil, "OVERLAY")
  titleBackgroundLeft:SetTexture(self.DIALOG_HEADER_TEXTURE)
  titleBackgroundLeft:SetWidth(30)
  titleBackgroundLeft:SetHeight(40)
  titleBackgroundLeft:SetPoint("TOPRIGHT", titleBackground, "TOPLEFT", 0, 0)
  titleBackgroundLeft:SetTexCoord(0.21, 0.31, 0, 0.63)

  local titleBackgroundRight = frame:CreateTexture(nil, "OVERLAY")
  titleBackgroundRight:SetTexture(self.DIALOG_HEADER_TEXTURE)
  titleBackgroundRight:SetWidth(30)
  titleBackgroundRight:SetHeight(40)
  titleBackgroundRight:SetPoint("TOPLEFT", titleBackground, "TOPRIGHT", 0, 0)
  titleBackgroundRight:SetTexCoord(0.67, 0.77, 0, 0.63)

  local title = frame:CreateFontString(nil, "OVERLAY")
  title:SetPoint("TOP", titleBackground, "TOP", 0, -14)
  self.SetUIFont(title, 12)
  title:SetText(text)
  title:SetTextColor(self.GOLD_R, self.GOLD_G, self.GOLD_B, 1)
  return title
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

function Style:GetWindowOpacity(profile)
  local opacity = profile and profile.windowOpacity
  if type(opacity) ~= "number" then return 0.9 end
  return max(0, min(1, opacity))
end

function Style:ApplyWindowBackground(frame, opacity)
  local backgroundTexture = rawget(frame, "skadaBg")
  if not backgroundTexture then
    backgroundTexture = frame:CreateTexture(nil, "BACKGROUND")
    backgroundTexture:SetTexture(self.WHITE)
    backgroundTexture:SetAllPoints(frame)
    rawset(frame, "skadaBg", backgroundTexture)
  end
  backgroundTexture:SetVertexColor(self.WINDOW_R, self.WINDOW_G, self.WINDOW_B)
  backgroundTexture:SetAlpha(opacity)
  return backgroundTexture
end

function Style:ApplyMeterBorder(frame, visible, red, green, blue)
  local edges = rawget(frame, "skadaBorderEdges")
  if not visible then
    if edges then
      local edgeIndex
      for edgeIndex = 1, table_getn(edges) do edges[edgeIndex]:Hide() end
    end
    return
  end

  if not edges then
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)

    edges = { top, bottom, left, right }
    rawset(frame, "skadaBorderEdges", edges)
    local edgeIndex
    for edgeIndex = 1, table_getn(edges) do edges[edgeIndex]:SetTexture(self.WHITE) end
  end

  local edgeIndex
  for edgeIndex = 1, table_getn(edges) do
    edges[edgeIndex]:SetVertexColor(red, green, blue)
    edges[edgeIndex]:SetAlpha(1)
    edges[edgeIndex]:Show()
  end
end

function Style:ApplyMeterWindow(frame, active, opacity)
  local profile = Skada.db.profile
  local borderStyle = profile.hideWindowBorder and "none" or profile.windowBorderStyle or "solid"
  local hideBorder = borderStyle == "none"
  local color = profile.windowBorderColor or { 0.10, 0.11, 0.14 }
  local borderR, borderG, borderB = color[1] or 0.10, color[2] or 0.11, color[3] or 0.14
  if active and borderStyle == "shadow" and profile.classColorMenus then
    borderR, borderG, borderB = self:GetAccentColor()
    borderR, borderG, borderB = borderR * 0.72, borderG * 0.72, borderB * 0.72
  end
  frame:SetBackdrop(nil)
  self:ApplyMeterBorder(frame, not hideBorder, borderR, borderG, borderB)
  self:ApplyWindowBackground(frame, opacity or 0.9)
  self:ApplyShadow(frame, borderStyle == "shadow")
end

function Style:ApplyHeader(window)
  if not window or not window.headerTexture then return end
  local profile = Skada.db.profile
  local active = window.manager and window.manager.visualActive == window
  local red, green, blue = 0.055, 0.060, 0.075
  if active then red, green, blue = 0.072, 0.078, 0.098 end
  if profile.classColorMenus then
    local accentRed, accentGreen, accentBlue = self:GetAccentColor()
    local strength = active and 0.18 or 0.11
    red, green, blue = red + accentRed * strength, green + accentGreen * strength, blue + accentBlue * strength
  end
  local opacity = self:GetWindowOpacity(window.db)
  window.headerTexture:SetTexture(self.WHITE)
  window.headerTexture:SetVertexColor(red, green, blue)
  window.headerTexture:SetAlpha(0.92 * opacity)
  if window.headerRule then
    local ruleRed, ruleGreen, ruleBlue = 0.34, 0.38, 0.47
    if active and profile.classColorMenus then ruleRed, ruleGreen, ruleBlue = self:GetAccentColor() end
    window.headerRule:SetVertexColor(ruleRed, ruleGreen, ruleBlue)
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
  local red, green, blue
  if active then
    red, green, blue = rawget(button, "skadaActiveR") or 0.20,
      rawget(button, "skadaActiveG") or 1,
      rawget(button, "skadaActiveB") or 0.20
    button:SetBackdropColor(red * 0.11, green * 0.11, blue * 0.11, 0.90)
  elseif hovered then
    button:SetBackdropColor(0.14, 0.15, 0.18, 0.94)
  else
    button:SetBackdropColor(0.035, 0.040, 0.052, 0.58)
  end

  if active then
    button:SetBackdropBorderColor(red, green, blue, 0.72)
  elseif Skada.db.profile.classColorMenus then
    red, green, blue = self:GetAccentColor()
    button:SetBackdropBorderColor(red, green, blue, hovered and 0.82 or 0.22)
  elseif hovered then
    button:SetBackdropBorderColor(0.50, 0.55, 0.66, 0.92)
  else
    button:SetBackdropBorderColor(0.20, 0.22, 0.27, 0.52)
  end

  local label = rawget(button, "text")
  if label then
    if active then
      label:SetTextColor(red, green, blue, 1)
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
      marker:SetVertexColor(red, green, blue, 1)
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

function Style:SetButtonActive(button, active, red, green, blue)
  if not button then return end
  active = active and true or false
  red, green, blue = red or 0.20, green or 1, blue or 0.20
  if rawget(button, "skadaActive") == active and
      rawget(button, "skadaActiveR") == red and rawget(button, "skadaActiveG") == green and
      rawget(button, "skadaActiveB") == blue then return end
  rawset(button, "skadaActive", active)
  rawset(button, "skadaActiveR", red)
  rawset(button, "skadaActiveG", green)
  rawset(button, "skadaActiveB", blue)
  self:ApplyButton(button, rawget(button, "skadaHovered"))
end
