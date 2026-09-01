local Skada = (_G or getfenv(0)).Skada

local Renderer = {}
Skada.UIRowRenderer = Renderer

local Common = Skada.Common
local getClickButton = Common.GetClickButton
local getWheelDelta = Common.GetWheelDelta
local setReadableFont = Common.SetFont
local Style = Skada.UIStyle

local abs = math.abs
local max = math.max
local min = math.min
local table_getn = table.getn

function Renderer:CreateRow(index)
  local owner = self
  local row = CreateFrame("Button", nil, self.frame)
  row.index = index
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:EnableMouseWheel(true)

  row.background = row:CreateTexture(nil, "BACKGROUND")
  row.background:SetAllPoints(row)
  row.background:SetTexture(Style:GetBarTexture())
  -- transparency rides on SetAlpha; see ApplyHeader
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
    if button == "RightButton" then owner:Back() else owner:SelectEntry(self.entry) end
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
  local i
  for i = table_getn(self.rows) + 1, count do self:CreateRow(i) end
end

function Renderer:ApplyLayout()
  local profile = self.db
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
  if self.clickCatcher then
    self.clickCatcher:ClearAllPoints()
    if profile.hideTitle then
      self.clickCatcher:SetPoint("TOPLEFT", self.frame, "TOPLEFT", Style.WINDOW_PADDING, 0)
      self.clickCatcher:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -Style.WINDOW_PADDING, 0)
      self.clickCatcher:SetHeight(profile.barHeight)
      self.clickCatcher:Show()
    else
      self.clickCatcher:Hide()
    end
  end

  self:EnsureRows(profile.rows)
  local i, row
  for i = 1, table_getn(self.rows) do
    row = self.rows[i]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", Style.WINDOW_PADDING, -headerHeight - (i - 1) * rowStep)
    row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -Style.WINDOW_PADDING, -headerHeight - (i - 1) * rowStep)
    row:SetHeight(profile.barHeight)
    row.icon:SetWidth(max(10, profile.barHeight - 4))
    row.icon:SetHeight(max(10, profile.barHeight - 4))
    setReadableFont(row.left, profile.fontSize)
    setReadableFont(row.right, profile.fontSize)
    if i <= profile.rows then row:Show() else row:Hide() end
  end

  setReadableFont(self.title, 13)
  Style:ApplyMeterWindow(self.frame, self.manager.visualActive == self, Style:GetWindowOpacity(profile))
  Style:ApplyHeader(self)
  if self.headerButtons then
    for i = 1, table_getn(self.headerButtons) do Style:ApplyButton(self.headerButtons[i]) end
  end

  if profile.locked then self.resizeButton:Hide() else self.resizeButton:Show() end
  if profile.visible then self.frame:Show() else self.frame:Hide() end
end

function Renderer:GetPinnedPlayerEntry(playerName, count)
  local offset = self.scrollOffset or 0
  if not playerName or offset <= 0 or self.view ~= "mode" or
      self.paintLive or self.detailActor then return nil end
  local i, entry
  for i = 1, min(offset, count or 0) do
    entry = self.display[i]
    if entry and entry.actor and not entry.spell and entry.actor.name == playerName then
      return entry, i
    end
  end
end

function Renderer:PaintRows()
  local profile = self.db
  local count = self.displayCount or 0
  local maxOffset = max(0, count - profile.rows)
  self.scrollOffset = min(maxOffset, max(0, self.scrollOffset or 0))

  self.animatedRows = min(profile.rows, max(0, count - self.scrollOffset))
  local maximum = self.paintMaximum or 1
  local targetKey = self.paintLive and Skada.Threat and Skada.Threat.targetKey or nil

  local globalProfile = Skada.db.profile
  local customColor = globalProfile.classColors == false and globalProfile.barColor or nil
  local barTexture = Style:GetBarTexture()
  local windowOpacity = Style:GetWindowOpacity(profile)
  local ease = Style:GetBarEase()
  local playerName = UnitName and UnitName("player") or nil
  local pinnedEntry, pinnedIndex = self:GetPinnedPlayerEntry(playerName, count)
  local i, displayIndex, row, entry, r, g, b
  for i = 1, profile.rows do
    row = self.rows[i]
    displayIndex = self.scrollOffset + i
    entry = self.display[displayIndex]
    row.skadaPinned = nil
    if pinnedEntry and i == 1 then
      entry = pinnedEntry
      displayIndex = pinnedIndex
      row.skadaPinned = true
    end
    row.entry = entry
    if entry then
      row:Show()
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
      if entry.spell then
        if entry.spell.id and Skada.Tracking then
          icon = Skada.Tracking:GetSpellIcon(entry.spell.id)
        end
        if not icon and (entry.spell.name == "Auto Attack" or entry.spell.name == "Auto Hit") then
          icon = Style.MELEE_ICON
        end
        if icon then iconKey = "spell:" .. tostring(icon) end
      elseif (entry.actor or entry.threatRow) and globalProfile.showClassIcons then
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
        row.smoothValue = row.smoothValue + (entry.value - row.smoothValue) * ease
        if abs(entry.value - row.smoothValue) < 0.01 then row.smoothValue = entry.value end
      end
      row.bar:SetValue(row.smoothValue)
      row.lastSetValue = row.smoothValue
      if entry.threatRow and playerName and entry.label == playerName then
        r, g, b = 1, 0.2, 0.2
      elseif entry.r then
        r, g, b = entry.r, entry.g, entry.b
      elseif entry.spell and globalProfile.spellColors ~= false and self.paintMode
          and self.paintMode.detail ~= "damageTargets" and self.paintMode.detail ~= "healTargets" then
        r, g, b = Style:GetSpellColor(displayIndex)
      elseif customColor then
        r, g, b = customColor[1], customColor[2], customColor[3]
      else
        r, g, b = Skada:GetClassColor(entry.class)
      end

      if r ~= row.lastR or g ~= row.lastG or b ~= row.lastB then
        row.lastR, row.lastG, row.lastB = r, g, b
        row.bar:SetStatusBarColor(r, g, b)
      end
      if row.lastAlpha ~= profile.barAlpha then
        row.lastAlpha = profile.barAlpha
        row.bar:SetAlpha(profile.barAlpha)
      end
      local borderR, borderG, borderB, borderA = 1, 1, 1, 0
      if globalProfile.highlightSelf and playerName and entry.label == playerName and not entry.spell then
        local color = globalProfile.highlightSelfColor
        borderR, borderG, borderB, borderA = color[1], color[2], color[3], 1
      elseif globalProfile.barBorder then
        local color = globalProfile.barBorderColor
        borderR, borderG, borderB, borderA = color[1], color[2], color[3], 1
      end
      if borderR ~= row.lastBorderR or borderG ~= row.lastBorderG or
          borderB ~= row.lastBorderB or borderA ~= row.lastBorderA then
        row.lastBorderR, row.lastBorderG = borderR, borderG
        row.lastBorderB, row.lastBorderA = borderB, borderA
        row.borderFrame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
      end
      local rank = entry.rank or displayIndex
      local label = entry.hideRank and entry.label or (rank .. ". " .. entry.label)
      if row.lastLabel ~= label then
        row.lastLabel = label
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
      row:Hide()

      if GameTooltip.IsOwned and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
      row.smoothEntry = nil
      row.smoothValue = nil
      row.lastLabel = nil
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
end

function Renderer:AnimateAll()
  local windows = self.windows
  local i
  for i = 1, table_getn(windows) do windows[i]:Animate() end
end

function Renderer:Animate()
  if not self.frame or not self.db.visible or not self.animatedRows then return end
  if Skada.db.profile.smoothBars == false then return end
  local ease = Style:GetBarEase()
  local rows = self.rows
  local i, row, entry
  for i = 1, self.animatedRows do
    row = rows[i]
    entry = row and row.entry
    if entry and row.smoothValue ~= nil then
      row.smoothValue = row.smoothValue + (entry.value - row.smoothValue) * ease
      if abs(entry.value - row.smoothValue) < 0.01 then row.smoothValue = entry.value end
      if row.smoothValue ~= row.lastSetValue then
        row.bar:SetValue(row.smoothValue)
        row.lastSetValue = row.smoothValue
      end
    end
  end
end
