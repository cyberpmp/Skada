local Skada = (_G or getfenv(0)).Skada

local SnapDock = {}
Skada.UISnapDock = SnapDock

local Style = Skada.UIStyle
local floor = math.floor
local max = math.max
local min = math.min
local table_getn = table.getn

local function rangesOverlap(firstStart, firstEnd, secondStart, secondEnd, tolerance)
  return firstEnd + tolerance >= secondStart and secondEnd + tolerance >= firstStart
end

function SnapDock.SnapWindow(manager, window)
  if not window or window.db.locked or window.db.snap == false or not window.frame.GetLeft then return end
  local left, bottom = window.frame:GetLeft(), window.frame:GetBottom()

  local scale = window.frame.GetEffectiveScale and window.frame:GetEffectiveScale() or 1
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  if left then left = left * scale end
  if bottom then bottom = bottom * scale end
  local width = window.frame:GetWidth() * scale
  local height = window.frame:GetHeight() * scale
  local uiScale = UIParent.GetScale and UIParent:GetScale() or 1
  if type(uiScale) ~= "number" or uiScale <= 0 then uiScale = 1 end
  local screenWidth, screenHeight = UIParent:GetWidth() * uiScale, UIParent:GetHeight() * uiScale
  if not left or not bottom or not width or not height or not screenWidth or not screenHeight then return end

  local right, top = left + width, bottom + height
  local distance = window.db.snapDistance or 12
  local gap = window.db.snapGap or 0
  local bestDistance, bestLeft, bestBottom, bestParent = distance + 1, left, bottom, nil
  local dockDistance, dockLeft, dockBottom, dockParent
  local function consider(candidateLeft, candidateBottom, parent)
    local delta = math.abs(candidateLeft - left) + math.abs(candidateBottom - bottom)
    if delta < bestDistance then
      bestDistance, bestLeft, bestBottom, bestParent = delta, candidateLeft, candidateBottom, parent
    end
  end

  if math.abs(left) <= distance then consider(0, bottom) end
  if math.abs(bottom) <= distance then consider(left, 0) end
  if math.abs(screenWidth - right) <= distance then consider(screenWidth - width, bottom) end
  if math.abs(screenHeight - top) <= distance then consider(left, screenHeight - height) end
  if math.abs(left) <= distance and math.abs(bottom) <= distance then consider(0, 0) end
  if math.abs(screenWidth - right) <= distance and math.abs(bottom) <= distance then consider(screenWidth - width, 0) end
  if math.abs(left) <= distance and math.abs(screenHeight - top) <= distance then consider(0, screenHeight - height) end
  if math.abs(screenWidth - right) <= distance and math.abs(screenHeight - top) <= distance then
    consider(screenWidth - width, screenHeight - height)
  end

  local windowIndex, other, otherLeft, otherBottom, otherWidth, otherHeight, otherRight, otherTop
  for windowIndex = 1, table_getn(manager.windows) do
    other = manager.windows[windowIndex]
    if other ~= window and other.db.visible and other.frame.GetLeft then
      otherLeft, otherBottom = other.frame:GetLeft(), other.frame:GetBottom()
      otherWidth, otherHeight = other.frame:GetWidth(), other.frame:GetHeight()
      if otherLeft and otherBottom and otherWidth and otherHeight then
        local otherScale = other.frame.GetEffectiveScale and other.frame:GetEffectiveScale() or 1
        if type(otherScale) ~= "number" or otherScale <= 0 then otherScale = 1 end
        otherLeft, otherBottom = otherLeft * otherScale, otherBottom * otherScale
        otherWidth, otherHeight = otherWidth * otherScale, otherHeight * otherScale
        otherRight, otherTop = otherLeft + otherWidth, otherBottom + otherHeight

        if left < otherRight and right > otherLeft and bottom < otherTop and top > otherBottom then
          local centerX, centerY = left + width * 0.5, bottom + height * 0.5
          local parentCenterX, parentCenterY = otherLeft + otherWidth * 0.5, otherBottom + otherHeight * 0.5
          local axisDistance = math.abs(centerX - parentCenterX) - math.abs(centerY - parentCenterY)
          local candidateLeft, candidateBottom
          if axisDistance >= 0 then
            candidateLeft = centerX < parentCenterX and (otherLeft - gap - width) or (otherRight + gap)
            candidateBottom = otherTop - height
          else
            candidateLeft = otherLeft
            candidateBottom = centerY < parentCenterY and (otherBottom - gap - height) or (otherTop + gap)
          end
          local approach = math.abs(centerX - parentCenterX) + math.abs(centerY - parentCenterY)
          if not dockParent or approach < dockDistance then
            dockDistance, dockLeft, dockBottom, dockParent = approach, candidateLeft, candidateBottom, other
          end
        end

        if rangesOverlap(bottom, top, otherBottom, otherTop, distance) then
          if math.abs(left - otherLeft) <= distance then consider(otherLeft, bottom, other) end
          if math.abs(left - otherRight) <= distance then consider(otherRight, bottom, other) end
          if math.abs(right - otherLeft) <= distance then consider(otherLeft - width, bottom, other) end
          if math.abs(right - otherRight) <= distance then consider(otherRight - width, bottom, other) end
        end
        if rangesOverlap(left, right, otherLeft, otherRight, distance) then
          if math.abs(bottom - otherBottom) <= distance then consider(left, otherBottom, other) end
          if math.abs(bottom - otherTop) <= distance then consider(left, otherTop, other) end
          if math.abs(top - otherBottom) <= distance then consider(left, otherBottom - height, other) end
          if math.abs(top - otherTop) <= distance then consider(left, otherTop - height, other) end
        end

        if math.abs(left - (otherRight + gap)) <= distance then
          if math.abs(top - otherTop) <= distance then consider(otherRight + gap, otherTop - height, other) end
          if math.abs(bottom - otherBottom) <= distance then consider(otherRight + gap, otherBottom, other) end
        end
        if math.abs(right - (otherLeft - gap)) <= distance then
          if math.abs(top - otherTop) <= distance then consider(otherLeft - gap - width, otherTop - height, other) end
          if math.abs(bottom - otherBottom) <= distance then consider(otherLeft - gap - width, otherBottom, other) end
        end
        if math.abs(bottom - (otherTop + gap)) <= distance and math.abs(left - otherLeft) <= distance then
          consider(otherLeft, otherTop + gap, other)
        end
        if math.abs(top - (otherBottom - gap)) <= distance and math.abs(left - otherLeft) <= distance then
          consider(otherLeft, otherBottom - gap - height, other)
        end
      end
    end
  end

  if dockParent then
    bestLeft, bestBottom, bestParent, bestDistance = dockLeft, dockBottom, dockParent, 0
  end

  if bestDistance <= distance then
    if bestParent and window.db.snapSize ~= false then
      local parentScale = bestParent.frame.GetEffectiveScale and bestParent.frame:GetEffectiveScale() or 1
      if type(parentScale) ~= "number" or parentScale <= 0 then parentScale = 1 end
      local parentWidth = bestParent.frame:GetWidth() * parentScale
      local parentHeight = bestParent.frame:GetHeight() * parentScale
      local parentLeft = bestParent.frame.GetLeft and bestParent.frame:GetLeft()
      local parentBottom = bestParent.frame.GetBottom and bestParent.frame:GetBottom()
      if parentWidth and parentHeight then
        local newWidth, newHeight = width, height
        local changed = false
        local beside, stacked = false, false
        if parentLeft and parentBottom then
          parentLeft, parentBottom = parentLeft * parentScale, parentBottom * parentScale
          beside = bestBottom < parentBottom + parentHeight and bestBottom + height > parentBottom
          stacked = bestLeft < parentLeft + parentWidth and bestLeft + width > parentLeft
        end
        if beside and not stacked then
          if math.abs(parentHeight - height) > 0.5 then newHeight = parentHeight changed = true end
        elseif stacked and not beside then
          if math.abs(parentWidth - width) > 0.5 then newWidth = parentWidth changed = true end
        else
          if math.abs(parentWidth - width) > 0.5 then newWidth = parentWidth changed = true end
          if math.abs(parentHeight - height) > 0.5 then newHeight = parentHeight changed = true end
        end
        if changed then
          window.frame:SetWidth(newWidth / scale)
          window.frame:SetHeight(newHeight / scale)
          return SnapDock.SnapWindow(manager, window)
        end
      end
    end
    window.frame:ClearAllPoints()

    local offsetX, offsetY = bestLeft / scale, bestBottom / scale
    window.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", offsetX, offsetY)
    window.db.point, window.db.relativePoint = "BOTTOMLEFT", "BOTTOMLEFT"
    window.db.x, window.db.y = offsetX, offsetY
  end
end

function SnapDock.PersistGeometry(window, persistPoint)
  local profile = window.db
  local frame = window.frame
  profile.width = max(Style.MIN_WINDOW_WIDTH, floor(frame:GetWidth() + 0.5))
  local rowStep = profile.barHeight + profile.barSpacing
  local headerHeight = profile.hideTitle and 0 or Style.HEADER_HEIGHT
  local contentHeight = frame:GetHeight() - headerHeight - Style.FOOTER_HEIGHT
  profile.rows = min(30, max(3, contentHeight / rowStep))
  if frame.SetHeight then
    frame:SetHeight(headerHeight + profile.rows * rowStep + Style.FOOTER_HEIGHT)
  end
  window.layoutDirty = true
  if persistPoint then
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    profile.point, profile.relativePoint, profile.x, profile.y = point, relativePoint, x, y
  end
  window.manager:SyncLegacy(window)
end
