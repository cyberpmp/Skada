local Skada = (_G or getfenv(0)).Skada

local Report = {}
Skada.UIReport = Report

local Common = Skada.Common
local setReadableFont = Common.SetFont
local Style = Skada.UIStyle

local table_getn = table.getn
local table_sort = table.sort

local FONT = Common.FONT

function Report:CreateHeaderButton(parent, spec)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(Style.HEADER_BUTTON_WIDTH)
  button:SetHeight(Style.HEADER_BUTTON_HEIGHT)
  button:SetHitRectInsets(-1, -1, -1, -1)

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  if spec.texture then
    button.skadaHasIcon = true
    button.icon:SetTexture(spec.texture)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  elseif spec.symbol then
    button.icon:Hide()
    button.symbolH = button:CreateTexture(nil, "OVERLAY")
    button.symbolH:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.symbolH:SetWidth(10)
    button.symbolH:SetHeight(2)
    button.symbolH:SetTexture(Style.WHITE)
    if spec.symbol == "plus" then
      button.symbolV = button:CreateTexture(nil, "OVERLAY")
      button.symbolV:SetPoint("CENTER", button, "CENTER", 0, 0)
      button.symbolV:SetWidth(2)
      button.symbolV:SetHeight(10)
      button.symbolV:SetTexture(Style.WHITE)
    end
  else
    button.icon:Hide()
    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text.skadaOffsetX = spec.textOffsetX or 0
    button.text.skadaOffsetY = spec.textOffsetY or 0
    button.text:SetPoint("CENTER", button, "CENTER", button.text.skadaOffsetX, button.text.skadaOffsetY)
    button.text:SetWidth(Style.HEADER_BUTTON_WIDTH)
    button.text:SetHeight(Style.HEADER_BUTTON_HEIGHT)
    button.text:SetJustifyH("CENTER")
    button.text:SetJustifyV("MIDDLE")
    setReadableFont(button.text, spec.textSize or 16)
    button.text:SetText(spec.text)
  end

  button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
  button.highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  button.highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  button.highlight:SetTexture(Style.WHITE)
  button.highlight:SetVertexColor(1, 1, 1, 0.12)
  button.highlight:SetBlendMode("ADD")

  if spec.activeMarker ~= false then
    button.activeMarker = button:CreateTexture(nil, "OVERLAY")
    button.activeMarker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    button.activeMarker:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.activeMarker:SetHeight(2)
    button.activeMarker:SetTexture(Style.WHITE)
    button.activeMarker:Hide()
  end

  Style:ApplyButton(button)
  button:SetAlpha(Style.HEADER_BUTTON_ALPHA)
  button:SetScript("OnClick", spec.click)
  button:SetScript("OnEnter", function(self)
    Style:ApplyButton(self, true)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(spec.title, 1, 1, 1)
    if spec.status then
      local status, r, g, b = spec.status()
      if status then GameTooltip:AddLine(status, r or 0.8, g or 0.8, b or 0.8) end
    end
    if spec.description then GameTooltip:AddLine(spec.description, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(self)
    Style:ApplyButton(self, false)
    self:SetAlpha(Style.HEADER_BUTTON_ALPHA)
    GameTooltip:Hide()
  end)
  return button
end

function Report:CreateActionMenu(owner, anchor)
  local menu = CreateFrame("Frame", nil, UIParent)
  menu:SetWidth(170)
  menu:SetFrameStrata("DIALOG")
  menu:EnableMouse(true)
  Style:ApplyFlatFrame(menu, 0.985, 0.16, 0.18, 0.23)
  Style:ApplyShadow(menu, true)
  menu.owner = owner
  menu.anchor = anchor
  menu.entries = {}
  menu.byKey = {}

  local function createEntry(key, label, click)
    local entry = CreateFrame("Button", nil, menu)
    entry:SetWidth(162)
    entry:SetHeight(22)
    entry:RegisterForClicks("LeftButtonUp")

    entry.highlight = entry:CreateTexture(nil, "BACKGROUND")
    entry.highlight:SetAllPoints(entry)
    entry.highlight:SetTexture(Style.WHITE)
    entry.highlight:SetVertexColor(1, 1, 1, 0.075)
    entry.highlight:Hide()

    entry.marker = entry:CreateTexture(nil, "ARTWORK")
    entry.marker:SetTexture(Style.WHITE)
    local ar, ag, ab = Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B
    entry.marker:SetVertexColor(ar, ag, ab, 0.92)
    entry.marker:SetWidth(2)
    entry.marker:SetPoint("TOPLEFT", entry, "TOPLEFT", 1, -3)
    entry.marker:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 1, 3)
    entry.marker:Hide()

    entry.rule = entry:CreateTexture(nil, "BACKGROUND")
    entry.rule:SetTexture(Style.WHITE)
    entry.rule:SetVertexColor(0.28, 0.31, 0.38, 0.42)
    entry.rule:SetHeight(1)
    entry.rule:SetPoint("BOTTOMLEFT", entry, "TOPLEFT", 4, 2)
    entry.rule:SetPoint("BOTTOMRIGHT", entry, "TOPRIGHT", -4, 2)
    entry.rule:Hide()

    entry.text = entry:CreateFontString(nil, "OVERLAY")
    entry.text:SetPoint("LEFT", entry, "LEFT", 7, 0)
    entry.text:SetPoint("RIGHT", entry, "RIGHT", -38, 0)
    entry.text:SetJustifyH("LEFT")
    setReadableFont(entry.text, 12)
    entry.text:SetText(label)
    entry.text:SetTextColor(0.84, 0.86, 0.90, 1)

    entry.value = entry:CreateFontString(nil, "OVERLAY")
    entry.value:SetPoint("RIGHT", entry, "RIGHT", -7, 0)
    entry.value:SetJustifyH("RIGHT")
    setReadableFont(entry.value, 11)

    entry:SetScript("OnEnter", function(self)
      self.highlight:Show()
      self.marker:Show()
      if key ~= "reset" then self.text:SetTextColor(0.98, 0.98, 1, 1) end
    end)
    entry:SetScript("OnLeave", function(self)
      self.highlight:Hide()
      self.marker:Hide()
      if key ~= "reset" then self.text:SetTextColor(0.84, 0.86, 0.90, 1) end
    end)
    entry:SetScript("OnClick", function()
      menu:Hide()
      click()
    end)
    menu.entries[table_getn(menu.entries) + 1] = entry
    menu.byKey[key] = entry
    return entry
  end

  createEntry("settings", "Settings", function()
    owner.manager:SetActive(owner)
    if Skada.Options then
      Skada.Options:Open()
      Skada.Options:SelectWindow(owner)
    end
  end)
  createEntry("logging", "Combat logging", function()
    owner.manager:SetActive(owner)
    Skada:SetCombatLogging(not Skada.combatLogging)
  end)
  createEntry("report", "Report meter", function()
    owner.manager:SetActive(owner)
    owner.manager:ShowReportPopup(owner)
  end)
  local newWindow = createEntry("new", "+  New window", function()
    owner.manager:SetActive(owner)
    owner.manager:CreateNew()
  end)
  newWindow.gapBefore = true
  createEntry("remove", "-  Remove window", function()
    owner.manager:SetActive(owner)
    owner.manager:RequestDelete(owner)
  end)
  local reset = createEntry("reset", "Reset all fight data", function()
    owner.manager:SetActive(owner)
    owner:ShowResetPopup()
  end)
  reset.gapBefore = true
  reset.text:SetTextColor(1, 0.48, 0.38, 1)

  function menu:Refresh()
    local canRemove = table_getn(owner.manager.windows) > 1
    local offset, i, entry = 4
    for i = 1, table_getn(self.entries) do
      entry = self.entries[i]
      if entry ~= self.byKey.remove or canRemove then
        if rawget(entry, "gapBefore") then
          offset = offset + 5
          entry.rule:Show()
        else
          entry.rule:Hide()
        end
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -offset)
        entry:Show()
        offset = offset + 22
      else
        entry:Hide()
      end
    end
    self:SetHeight(offset + 4)
    self.byKey.logging.value:SetText(Skada.combatLogging and "On" or "Off")
    if Skada.combatLogging then
      self.byKey.logging.value:SetTextColor(0.20, 1, 0.20, 1)
    else
      self.byKey.logging.value:SetTextColor(0.68, 0.68, 0.72, 1)
    end
  end

  function menu:Toggle()
    if self:IsShown() then
      self:Hide()
      return
    end
    self:Refresh()
    self:ClearAllPoints()
    self:SetPoint("TOPRIGHT", self.anchor, "BOTTOMRIGHT", 0, -4)
    self:Show()
    Style:FadeIn(self, 0.45, 0.10, 1)
  end

  menu:Hide()
  return menu
end

function Report:ShowResetPopup()
  if StaticPopup_Show then
    StaticPopup_Show("SKADA_RESET_DATA")
  else
    Skada.Data:Reset()
  end
end

local function trimText(value)
  return Common.Trim(value) or ""
end

function Report:BuildReportLines(window)
  local mode = Skada.Modes:Get(window.db.mode)
  local lines = {}
  lines[1] = "Skada - " .. mode.title
  if mode.live then
    lines[1] = lines[1] .. " (" .. (Skada.Threat and Skada.Threat:GetTitle() or "live") .. ")"
    local rows = Skada.Threat and Skada.Threat.rows or {}
    local i, row
    for i = 1, table_getn(rows) do
      row = rows[i]
      lines[table_getn(lines) + 1] = tostring(i) .. ". " .. row.name .. " " ..
        Skada.UIPresenter:FormatThreatText(row)
    end
  else
    lines[1] = lines[1] .. " (" .. Skada.Data:GetSegmentLabel(window.db.segment) .. ")"
    local set = Skada.Data:GetSelectedSet(window.db.segment)
    local list, i, actor, value, item
    list = {}
    for i = 1, table_getn(set.actorList) do
      actor = set.actorList[i]
      value = Skada.Modes:GetActorValue(mode, actor)
      if value > 0 then
        item = { actor = actor, value = value }
        list[table_getn(list) + 1] = item
      end
    end
    table_sort(list, function(a, b) return a.value == b.value and a.actor.name < b.actor.name or a.value > b.value end)
    for i = 1, table_getn(list) do
      actor = list[i].actor
      lines[table_getn(lines) + 1] = tostring(i) .. ". " .. actor.name .. " " ..
        Skada.Modes:GetActorText(mode, actor, set)
    end
  end
  if table_getn(lines) == 1 then lines[2] = "(no data)" end
  return lines
end

function Report:Report(window, channel, target)
  if not SendChatMessage then
    Skada:Print("Chat reporting is unavailable on this client.")
    return
  end
  if channel == "WHISPER" then
    target = trimText(target)
    if target == "" then
      Skada:Print("Enter a player name for Whisper.")
      return
    end
  end
  local lines = self:BuildReportLines(window)
  local i
  for i = 1, table_getn(lines) do SendChatMessage(lines[i], channel, nil, target) end
  if self.reportPopup then self.reportPopup:Hide() end
end

function Report:ShowReportPopup(window)

  if self.reportPopup and not self.reportPopup.title then self.reportPopup = nil end
  if not self.reportPopup then
    local popup = CreateFrame("Frame", "SkadaReportPopup", UIParent)
    self.reportPopup = popup
    popup:SetWidth(360)
    popup:SetHeight(112)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetFrameStrata("DIALOG")
    Style:ApplyFlatFrame(popup, 0.985, 0.16, 0.18, 0.23)
    Style:ApplyShadow(popup, true)

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -8)
    setReadableFont(title, 14)
    title:SetTextColor(0.95, 0.96, 0.99, 1)
    title:SetText("Report Skada meter")
    popup.title = title

    local subtitle = popup:CreateFontString(nil, "OVERLAY")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    setReadableFont(subtitle, 10)
    subtitle:SetTextColor(Style.MUTED_R, Style.MUTED_G, Style.MUTED_B, 1)
    subtitle:SetText("Send the current view")
    popup.subtitle = subtitle

    local whisper = CreateFrame("EditBox", nil, popup)
    whisper:SetWidth(110)
    whisper:SetHeight(20)
    whisper:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 10, 10)
    whisper:SetAutoFocus(false)
    whisper:SetTextInsets(5, 5, 0, 0)
    whisper:SetBackdrop(Style.FLAT_BACKDROP)
    whisper:SetBackdropColor(0.055, 0.060, 0.075, 1)
    whisper:SetBackdropBorderColor(0.12, 0.13, 0.16, 1)
    whisper:SetTextColor(1, 1, 1, 1)
    whisper:SetFont(FONT, 12, "OUTLINE")
    popup.whisper = whisper

    local hint = popup:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("LEFT", whisper, "RIGHT", 6, 0)
    setReadableFont(hint, 11)
    hint:SetText("Whisper target")
    hint:SetTextColor(Style.MUTED_R, Style.MUTED_G, Style.MUTED_B, 1)

    local channels = {
      { "Guild", "GUILD" }, { "Party/Raid", "GROUP" }, { "Say", "SAY" }, { "Whisper", "WHISPER" },
    }
    local i, button, spec
    for i = 1, table_getn(channels) do
      spec = channels[i]
      local channelLabel, channelType = spec[1], spec[2]
      button = CreateFrame("Button", nil, popup)
      button:SetWidth(i == 2 and 78 or 62)
      button:SetHeight(22)
      button:SetPoint("TOPLEFT", popup, "TOPLEFT", 10 + (i - 1) * 84, -40)
      button:SetScript("OnClick", function()
        local destination = channelType == "GROUP" and ((GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 and "RAID" or "PARTY") or channelType
        self:Report(popup.window, destination, popup.whisper:GetText())
      end)
      button.text = button:CreateFontString(nil, "OVERLAY")
      button.text:SetAllPoints(button)
      setReadableFont(button.text, 11)
      button.text:SetText(channelLabel)
      Style:ApplyButton(button)
      button:SetScript("OnEnter", function(self) Style:ApplyButton(self, true) end)
      button:SetScript("OnLeave", function(self) Style:ApplyButton(self, false) end)
    end
    local close = CreateFrame("Button", nil, popup)
    close:SetWidth(18)
    close:SetHeight(18)
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
    Style:ApplyButton(close)
    close.text = close:CreateFontString(nil, "OVERLAY")
    close.text:SetAllPoints(close)
    setReadableFont(close.text, 13)
    close.text:SetText("x")
    close.text:SetTextColor(0.72, 0.74, 0.79, 1)
    close:SetScript("OnEnter", function(self) Style:ApplyButton(self, true) end)
    close:SetScript("OnLeave", function(self) Style:ApplyButton(self, false) end)
    close:SetScript("OnClick", function() popup:Hide() end)
  end
  self.reportPopup.window = window
  self.reportPopup.title:SetText("Report " .. (window.db.name or "Skada") .. " meter")
  self.reportPopup:Show()
  Style:FadeIn(self.reportPopup, 0.42, 0.11, 1)
end
