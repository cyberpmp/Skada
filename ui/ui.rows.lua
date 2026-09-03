local Skada = (_G or getfenv(0)).Skada

local Renderer = {}
Skada.UIRowRenderer = Renderer

local Common = Skada.Common
local getClickButton = Common.GetClickButton
local getWheelDelta = Common.GetWheelDelta
local setReadableFont = Common.SetFont
local Style = Skada.UIStyle
local BAR_EASE = Style.BAR_EASE
local getVisibleRowCount = Skada.WindowConfig.GetVisibleRowCount

local abs = math.abs
local floor = math.floor
local max = math.max
local min = math.min
local table_getn = table.getn

local function getPartialRowHeight(profile, rowStep)
  local rows = tonumber(profile.rows) or 0
  local strip = (rows - floor(rows)) * rowStep - profile.barSpacing
  if strip + 0.000001 >= 6 then return strip end
  return 0
end

function Renderer:CreateRow(index)
  local owner = self
  local row = CreateFrame("Button", nil, self.frame)
  row.index = index
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:EnableMouseWheel(true)

  row.background = row:CreateTexture(nil, "BACKGROUND")
  row.background:SetAllPoints(row)
  row.background:SetTexture(Style:GetBarTexture())
  row.background:SetVertexColor(Style.ROW_R, Style.ROW_G, Style.ROW_B)
  row.background:SetAlpha(0.94 * Style:GetWindowOpacity(self.db))

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints(row)
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetValue(0)
  row.bar:SetStatusBarTexture(Style:GetBarTexture())
  row.bar:SetFrameLevel(row:GetFrameLevel())

  row.borderFrame = CreateFrame("Frame", nil, row)
  row.borderFrame:SetAllPoints(row)
  row.borderFrame:SetFrameLevel(row:GetFrameLevel() + 1)
  row.borderFrame:SetBackdrop(Style.FLAT_BACKDROP)
  row.borderFrame:SetBackdropColor(0, 0, 0, 0)
  row.borderFrame:SetBackdropBorderColor(1, 1, 1, 0)

  row.textLayer = CreateFrame("Frame", nil, row)
  row.textLayer:SetAllPoints(row)
  row.textLayer:SetFrameLevel(row:GetFrameLevel() + 2)

  row.icon = row.textLayer:CreateTexture(nil, "ARTWORK")
  row.icon:SetWidth(14)
  row.icon:SetHeight(14)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.icon:SetAlpha(0.92)
  row.icon:Hide()

  row.right = row.textLayer:CreateFontString(nil, "OVERLAY")
  row.right:SetPoint("RIGHT", row, "RIGHT", -5, 0)
  row.right:SetJustifyH("RIGHT")
  row.right:SetTextColor(0.76, 0.79, 0.84, 1)

  row.left = row.textLayer:CreateFontString(nil, "OVERLAY")
  row.left:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.left:SetPoint("RIGHT", row.right, "LEFT", -5, 0)
  row.left:SetJustifyH("LEFT")
  row.left:SetTextColor(0.94, 0.95, 0.97, 1)

  row.hover = row.textLayer:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints(row)
  row.hover:SetTexture(Style.WHITE)
  row.hover:SetVertexColor(1, 1, 1, 0.055)
  row.hover:SetBlendMode("ADD")
  row.hover:Hide()

  row:SetScript("OnClick", function(self, button)
    button = getClickButton(button)
    owner.manager:SetActive(owner)
    if owner.windowWasDragged then
      owner.windowWasDragged = false
      return
    end
    if button == "RightButton" then
      if owner.actionMenu then owner.actionMenu:Hide() end
      owner:Back()
    else
      owner:SelectEntry(self.entry)
    end
  end)
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnMouseDown", function() owner.windowWasDragged = false end)
  row:SetScript("OnDragStart", function()
    owner:BeginWindowDrag("windowWasDragged")
  end)
  row:SetScript("OnDragStop", function()
    owner:EndWindowDrag()
  end)
  row:SetScript("OnMouseWheel", function(_, delta)
    delta = getWheelDelta(delta)
    if delta ~= 0 then owner:Scroll(delta) end
  end)
  row:SetScript("OnEnter", function(self)
    self.hover:Show()
    owner:ShowEntryTooltip(self)
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:Hide()
    GameTooltip:Hide()
  end)

  self.rows[index] = row
  return row
end

function Renderer:EnsureRows(count)
  local rowIndex
  for rowIndex = table_getn(self.rows) + 1, count do self:CreateRow(rowIndex) end
end

function Renderer:ApplyLayout()
  local profile = self.db
  local visibleRows = getVisibleRowCount(profile)
  profile.width = max(Style.MIN_WINDOW_WIDTH, profile.width or Style.MIN_WINDOW_WIDTH)
  local rowStep = profile.barHeight + profile.barSpacing
  local headerHeight = profile.hideTitle and 0 or Style.HEADER_HEIGHT
  local height = headerHeight + profile.rows * rowStep + Style.FOOTER_HEIGHT
  self.frame:SetWidth(profile.width)
  self.frame:SetHeight(height)
  self.frame:ClearAllPoints()
  self.frame:SetPoint(profile.point, UIParent, profile.relativePoint, profile.x, profile.y)
  self.frame:SetMovable(not profile.locked)
  self.frame:SetResizable(not profile.locked)
  self.frame:SetMinResize(Style.MIN_WINDOW_WIDTH, headerHeight + 3 * rowStep + Style.FOOTER_HEIGHT)
  self.frame:SetMaxResize(600, headerHeight + 30 * rowStep + Style.FOOTER_HEIGHT)
  self.frame:EnableMouse(true)
  self.frame:SetClampedToScreen(true)

  if profile.hideTitle then
    self.header:Hide()
  else
    self.header:Show()
  end
  local partialHeight = getPartialRowHeight(profile, rowStep)
  self:EnsureRows(visibleRows + (partialHeight > 0 and 1 or 0))
  local rowIndex, row, buttonIndex
  for rowIndex = 1, table_getn(self.rows) do
    row = self.rows[rowIndex]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", Style.WINDOW_PADDING, -headerHeight - (rowIndex - 1) * rowStep)
    row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -Style.WINDOW_PADDING, -headerHeight - (rowIndex - 1) * rowStep)
    local rowHeight = profile.barHeight
    if partialHeight > 0 and rowIndex == visibleRows + 1 then rowHeight = partialHeight end
    row:SetHeight(rowHeight)
    row.icon:SetWidth(max(10, profile.barHeight - 4))
    row.icon:SetHeight(max(10, profile.barHeight - 4))
    setReadableFont(row.left, profile.fontSize)
    setReadableFont(row.right, profile.fontSize)
    if rowIndex <= visibleRows + (partialHeight > 0 and 1 or 0) then row:Show() else row:Hide() end
  end

  setReadableFont(self.title, 13)
  Style:ApplyMeterWindow(self.frame, self.manager.visualActive == self, Style:GetWindowOpacity(profile))
  Style:ApplyHeader(self)
  if self.headerButtons then
    for buttonIndex = 1, table_getn(self.headerButtons) do Style:ApplyButton(self.headerButtons[buttonIndex]) end
  end

  if profile.locked then self.resizeButton:Hide() else self.resizeButton:Show() end
  if profile.visible then self.frame:Show() else self.frame:Hide() end
end

function Renderer:GetPinnedPlayerEntry(playerName, count)
  local offset = self.scrollOffset or 0
  if not playerName or offset <= 0 or self.view ~= "mode" or
      self.paintLive or self.detailActor then return nil end
  local displayIndex, entry
  for displayIndex = 1, min(offset, count or 0) do
    entry = self.display[displayIndex]
    if entry and entry.actor and not entry.spell and entry.actor.name == playerName then
      return entry, displayIndex
    end
  end
end

function Renderer:PaintRows()
  local profile = self.db
  local count = self.displayCount or 0
  local visibleRows = getVisibleRowCount(profile)
  local partialHeight = getPartialRowHeight(profile, profile.barHeight + profile.barSpacing)
  local paintRows = visibleRows + (partialHeight > 0 and 1 or 0)
  paintRows = min(paintRows, table_getn(self.rows))
  local maxOffset = max(0, count - visibleRows)
  self.scrollOffset = min(maxOffset, max(0, floor(self.scrollOffset or 0)))

  self.animatedRows = min(paintRows, max(0, count - self.scrollOffset))
  local maximum = self.paintMaximum or 1
  local targetKey = self.paintLive and Skada.Threat and Skada.Threat.targetKey or nil

  local globalProfile = Skada.db.profile
  local customColor = globalProfile.classColors == false and globalProfile.barColor or nil
  local highlightSelf = globalProfile.highlightSelf
  local highlightSelfColor = globalProfile.highlightSelfColor
  local barBorder = globalProfile.barBorder
  local barBorderColor = globalProfile.barBorderColor
  local showClassIcons = globalProfile.showClassIcons
  local spellColorsEnabled = globalProfile.spellColors ~= false
  local barAlpha = profile.barAlpha
  local barTexture = Style:GetBarTexture()
  local windowOpacity = Style:GetWindowOpacity(profile)
  local animationThreshold = max(0.01, maximum / max(1, (profile.width or 1) * 4))
  self.animationThreshold = animationThreshold
  local hasAnimatingRows = false
  local playerName = Skada.Data and Skada.Data:GetPlayerName()
  local pinnedEntry, pinnedIndex = self:GetPinnedPlayerEntry(playerName, count)
  local rowIndex, displayIndex, row, entry, red, green, blue
  for rowIndex = 1, paintRows do
    row = self.rows[rowIndex]
    displayIndex = self.scrollOffset + rowIndex
    entry = self.display[displayIndex]
    row.skadaPinned = nil
    local partial = rowIndex > visibleRows
    if pinnedEntry and rowIndex == 1 then
      entry = pinnedEntry
      displayIndex = pinnedIndex
      row.skadaPinned = true
    end
    row.entry = entry
    if entry then
      if not row:IsShown() then row:Show() end
      if not partial then row.textLayer:Show() end
      if row.lastBarTexture ~= barTexture or row.lastOpacity ~= windowOpacity then
        row.lastBarTexture = barTexture
        row.lastOpacity = windowOpacity
        row.bar:SetStatusBarTexture(barTexture)
        row.background:SetTexture(barTexture)
        row.background:SetVertexColor(Style.ROW_R, Style.ROW_G, Style.ROW_B)
        row.background:SetAlpha(0.94 * windowOpacity)
      end
      if row.lastMax ~= maximum then
        row.lastMax = maximum
        row.bar:SetMinMaxValues(0, maximum)
      end
      local icon, iconKey, iconCoords
      if partial then
        row.textLayer:Hide()
        if row.lastIcon ~= nil then
          row.lastIcon = nil
          row.icon:Hide()
          row.left:ClearAllPoints()
          row.left:SetPoint("LEFT", row, "LEFT", 4, 0)
          row.left:SetPoint("RIGHT", row.right, "LEFT", -5, 0)
        end
      elseif entry.spell then
        if entry.spell.id and Skada.Tracking then
          icon = Skada.Tracking:GetSpellIcon(entry.spell.id)
        end
        if not icon and (entry.spell.name == "Auto Attack" or entry.spell.name == "Auto Hit") then
          icon = Style.MELEE_ICON
        end
        if icon then iconKey = "spell:" .. tostring(icon) end
      elseif (entry.actor or entry.threatRow) and showClassIcons then
        iconCoords = Style.CLASS_ICON_TCOORDS[entry.class]
        if iconCoords then
          icon = Style.CLASS_ICONS
          iconKey = "class:" .. tostring(entry.class)
        end
      end
      if iconKey ~= row.lastIcon then
        row.lastIcon = iconKey
        if icon then
          row.icon:SetTexture(icon)
          if iconCoords then
            row.icon:SetTexCoord(iconCoords[1], iconCoords[2], iconCoords[3], iconCoords[4])
          else
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          end
          row.icon:Show()
          row.left:ClearAllPoints()
          row.left:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
          row.left:SetPoint("RIGHT", row.right, "LEFT", -5, 0)
        else
          row.icon:Hide()
          row.left:ClearAllPoints()
          row.left:SetPoint("LEFT", row, "LEFT", 4, 0)
          row.left:SetPoint("RIGHT", row.right, "LEFT", -5, 0)
        end
      end
      if row.smoothEntry ~= entry or row.smoothView ~= self.view or
         row.smoothDetail ~= self.detailActor or row.smoothMode ~= self.db.mode or
         row.smoothSegment ~= self.db.segment or row.smoothTarget ~= targetKey then
        row.smoothEntry = entry
        row.smoothView = self.view
        row.smoothDetail = self.detailActor
        row.smoothMode = self.db.mode
        row.smoothSegment = self.db.segment
        row.smoothTarget = targetKey
        row.smoothValue = entry.value
      else
        row.smoothValue = row.smoothValue + (entry.value - row.smoothValue) * BAR_EASE
        if abs(entry.value - row.smoothValue) < animationThreshold then row.smoothValue = entry.value end
      end
      if row.smoothValue ~= row.lastSetValue then
        row.bar:SetValue(row.smoothValue)
        row.lastSetValue = row.smoothValue
      end
      if row.smoothValue ~= entry.value then
        hasAnimatingRows = true
      end
      if entry.threatRow and playerName and entry.label == playerName then
        red, green, blue = 1, 0.2, 0.2
      elseif entry.r then
        red, green, blue = entry.r, entry.g, entry.b
      elseif entry.spell and spellColorsEnabled and self.paintMode
          and self.paintMode.detail ~= "damageTargets" and self.paintMode.detail ~= "healTargets" then
        red, green, blue = Style:GetSpellColor(displayIndex)
      elseif customColor then
        red, green, blue = customColor[1], customColor[2], customColor[3]
      else
        red, green, blue = Skada:GetClassColor(entry.class)
      end

      if red ~= row.lastR or green ~= row.lastG or blue ~= row.lastB then
        row.lastR, row.lastG, row.lastB = red, green, blue
        row.bar:SetStatusBarColor(red, green, blue)
      end
      if row.lastAlpha ~= barAlpha then
        row.lastAlpha = barAlpha
        row.bar:SetAlpha(barAlpha)
      end
      local borderR, borderG, borderB, borderA = 1, 1, 1, 0
      if highlightSelf and playerName and entry.label == playerName and not entry.spell then
        borderR, borderG, borderB, borderA = highlightSelfColor[1], highlightSelfColor[2], highlightSelfColor[3], 1
      elseif barBorder then
        borderR, borderG, borderB, borderA = barBorderColor[1], barBorderColor[2], barBorderColor[3], 1
      end
      if borderR ~= row.lastBorderR or borderG ~= row.lastBorderG or
          borderB ~= row.lastBorderB or borderA ~= row.lastBorderA then
        row.lastBorderR, row.lastBorderG = borderR, borderG
        row.lastBorderB, row.lastBorderA = borderB, borderA
        row.borderFrame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
      end
      local rank = entry.rank or displayIndex
      if row.lastEntryLabel ~= entry.label or row.lastRank ~= rank or
          row.lastHideRank ~= entry.hideRank then
        row.lastEntryLabel = entry.label
        row.lastRank = rank
        row.lastHideRank = entry.hideRank
        local label = entry.hideRank and entry.label or (rank .. ". " .. entry.label)
        row.left:SetText(label)
      end
      local text = entry.text
      if text == nil then
        text = self:GetEntryText(entry)
        entry.text = text
      end
      if row.lastText ~= text then
        row.lastText = text
        row.right:SetText(text)

        local cap = (profile.width - 8) - 60
        if (row.right:GetStringWidth() or 0) > cap then
          row.right:SetWidth(cap)
        else
          row.right:SetWidth(0)
        end
      end
    else
      if row:IsShown() then row:Hide() end

      if GameTooltip.IsOwned and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
      row.smoothEntry = nil
      row.smoothValue = nil
      row.lastEntryLabel = nil
      row.lastRank = nil
      row.lastHideRank = nil
      row.lastText = nil
      if row.lastIcon ~= nil then
        row.lastIcon = nil
        row.icon:Hide()
        row.left:ClearAllPoints()
        row.left:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -5, 0)
      end
    end
  end
  self.hasAnimatingRows = hasAnimatingRows
end

function Renderer:AnimateAll()
  if not self.hasActiveAnimations then return false end
  local windows = self.windows
  local windowIndex, active
  active = false
  for windowIndex = 1, table_getn(windows) do
    if windows[windowIndex].hasAnimatingRows and windows[windowIndex]:Animate() then active = true end
  end
  self.hasActiveAnimations = active
  return active
end

function Renderer:Animate()
  if not self.frame or not self.db or self.broken or not self.db.visible or not self.animatedRows then
    self.hasAnimatingRows = false
    return false
  end
  local threshold = self.animationThreshold or 0.01
  local rows = self.rows
  local rowIndex, row, entry, active
  active = false
  for rowIndex = 1, self.animatedRows do
    row = rows[rowIndex]
    entry = row and row.entry
    if entry and entry.value ~= nil and row.smoothValue ~= nil then
      row.smoothValue = row.smoothValue + (entry.value - row.smoothValue) * BAR_EASE
      if abs(entry.value - row.smoothValue) < threshold then row.smoothValue = entry.value end
      if row.smoothValue ~= row.lastSetValue then
        row.bar:SetValue(row.smoothValue)
        row.lastSetValue = row.smoothValue
      end
      if row.smoothValue ~= entry.value then active = true end
    end
  end
  self.hasAnimatingRows = active
  return active
end
