local Skada = (_G or getfenv(0)).Skada

local Report = {}
Skada.UIReport = Report

local Common = Skada.Common
local setReadableFont = Common.SetFont
local Style = Skada.UIStyle

local table_getn = table.getn
local table_insert = table.insert
local table_sort = table.sort

local setUiFont = Style.SetUIFont

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
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", function(self, clickButton)
    clickButton = Common.GetClickButton(clickButton)
    if clickButton == "RightButton" then
      if spec.rightClick then spec.rightClick(self) end
    else
      spec.click(self)
    end
  end)
  button:SetScript("OnEnter", function(self)
    Style:ApplyButton(self, true)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(spec.title, 1, 1, 1)
    if spec.status then
      local status, red, green, blue = spec.status()
      if status then GameTooltip:AddLine(status, red or 0.8, green or 0.8, blue or 0.8) end
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
    local accentRed, accentGreen, accentBlue = Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B
    entry.marker:SetVertexColor(accentRed, accentGreen, accentBlue, 0.92)
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
    table_insert(menu.entries, entry)
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
    local offset, entryIndex, entry = 4
    for entryIndex = 1, table_getn(self.entries) do
      entry = self.entries[entryIndex]
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
    local rowIndex, row
    for rowIndex = 1, table_getn(rows) do
      row = rows[rowIndex]
      table_insert(lines, tostring(rowIndex) .. ". " .. row.name .. " " ..
        Skada.UIPresenter:FormatThreatText(row))
    end
  else
    lines[1] = lines[1] .. " (" .. Skada.Data:GetSegmentLabel(window.db.segment) .. ")"
    local set = Skada.Data:GetSelectedSet(window.db.segment)
    local list, actorIndex, lineIndex, actor, value, item
    list = {}
    for actorIndex = 1, table_getn(set.actorList) do
      actor = set.actorList[actorIndex]
      value = Skada.Modes:GetActorValue(mode, actor)
      if value > 0 then
        item = { actor = actor, value = value }
        table_insert(list, item)
      end
    end
    table_sort(list, function(left, right) return left.value == right.value and left.actor.name < right.actor.name or left.value > right.value end)
    for lineIndex = 1, table_getn(list) do
      actor = list[lineIndex].actor
      table_insert(lines, tostring(lineIndex) .. ". " .. actor.name .. " " ..
        Skada.Modes:GetActorText(mode, actor, set))
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
  local lineIndex
  for lineIndex = 1, table_getn(lines) do SendChatMessage(lines[lineIndex], channel, nil, target) end
  if self.reportPopup then self.reportPopup:Hide() end
end

function Report:ShowReportPopup(window)
  if self.reportPopup and not self.reportPopup.title then self.reportPopup = nil end
  if not self.reportPopup then
    local popup = CreateFrame("Frame", "SkadaReportPopup", UIParent)
    self.reportPopup = popup
    popup:SetWidth(380)
    popup:SetHeight(185)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function() popup:StartMoving() end)
    popup:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)
    Style:ApplyDialogFrame(popup)
    if UISpecialFrames then table_insert(UISpecialFrames, "SkadaReportPopup") end

    popup.dialogTitle = Style:CreateDialogTitle(popup, "Skada")

    local pane = CreateFrame("Frame", nil, popup)
    pane:SetWidth(346)
    pane:SetHeight(100)
    pane:SetPoint("TOPLEFT", popup, "TOPLEFT", 17, -36)
    Style:ApplyPane(pane)
    popup.pane = pane

    local title = pane:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -9)
    setUiFont(title, 16)
    title:SetTextColor(0.95, 0.96, 0.99, 1)
    title:SetText("Report Skada meter")
    popup.title = title

    local subtitle = pane:CreateFontString(nil, "OVERLAY")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    setUiFont(subtitle, 11)
    subtitle:SetTextColor(Style.MUTED_R, Style.MUTED_G, Style.MUTED_B, 1)
    subtitle:SetText("Send the current view to a chat channel.")
    popup.subtitle = subtitle

    local channels = {
      { "Guild", "GUILD" }, { "Party/Raid", "GROUP" },
      { "Say", "SAY" }, { "Whisper", "WHISPER" },
    }
    popup.channelButtons = {}
    local channelIndex, button, previous, spec
    for channelIndex = 1, table_getn(channels) do
      spec = channels[channelIndex]
      local channelLabel, channelType = spec[1], spec[2]
      button = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
      button:SetWidth(77)
      button:SetHeight(20)
      if previous then
        button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
      else
        button:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 10, 10)
      end
      button:SetText(channelLabel)
      button:SetScript("OnClick", function()
        local destination = channelType == "GROUP" and ((GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 and "RAID" or "PARTY") or channelType
        self:Report(popup.window, destination, popup.whisper:GetText())
      end)
      table_insert(popup.channelButtons, button)
      previous = button
    end

    local targetPane = CreateFrame("Frame", nil, popup)
    targetPane:SetHeight(24)
    targetPane:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 15, 15)
    targetPane:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -137, 15)
    Style:ApplyPane(targetPane, 1)
    popup.targetPane = targetPane

    local hint = targetPane:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("LEFT", targetPane, "LEFT", 7, 0)
    setUiFont(hint, 11)
    hint:SetText("Whisper:")
    hint:SetTextColor(Style.GOLD_R, Style.GOLD_G, Style.GOLD_B, 1)

    local whisper = CreateFrame("EditBox", nil, targetPane)
    whisper:SetWidth(150)
    whisper:SetHeight(18)
    whisper:SetPoint("RIGHT", targetPane, "RIGHT", -6, 0)
    whisper:SetAutoFocus(false)
    whisper:SetTextInsets(5, 5, 0, 0)
    whisper:SetBackdrop(Style.FLAT_BACKDROP)
    whisper:SetBackdropColor(0.055, 0.060, 0.075, 1)
    whisper:SetBackdropBorderColor(0.12, 0.13, 0.16, 1)
    whisper:SetTextColor(1, 1, 1, 1)
    setUiFont(whisper, 12)
    whisper:SetScript("OnEnterPressed", function()
      self:Report(popup.window, "WHISPER", whisper:GetText())
    end)
    whisper:SetScript("OnEscapePressed", function() whisper:ClearFocus() end)
    popup.whisper = whisper

    local close = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    close:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -27, 17)
    close:SetWidth(100)
    close:SetHeight(20)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function()
      if PlaySound then PlaySound("gsTitleOptionExit") end
      popup:Hide()
    end)
    popup.close = close

    popup:SetScript("OnHide", function() whisper:ClearFocus() end)
  end
  self.reportPopup.window = window
  self.reportPopup.title:SetText("Report " .. (window.db.name or "Skada") .. " meter")
  self.reportPopup:Show()
  Style:FadeIn(self.reportPopup, 0.38, 0.13, 1)
end
