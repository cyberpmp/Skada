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

  local i, other, oLeft, oBottom, oWidth, oHeight, oRight, oTop
  for i = 1, table_getn(manager.windows) do
    other = manager.windows[i]
    if other ~= window and other.db.visible and other.frame.GetLeft then
      oLeft, oBottom = other.frame:GetLeft(), other.frame:GetBottom()
      oWidth, oHeight = other.frame:GetWidth(), other.frame:GetHeight()
      if oLeft and oBottom and oWidth and oHeight then
        local oScale = other.frame.GetEffectiveScale and other.frame:GetEffectiveScale() or 1
        if type(oScale) ~= "number" or oScale <= 0 then oScale = 1 end
        oLeft, oBottom = oLeft * oScale, oBottom * oScale
        oWidth, oHeight = oWidth * oScale, oHeight * oScale
        oRight, oTop = oLeft + oWidth, oBottom + oHeight

        if left < oRight and right > oLeft and bottom < oTop and top > oBottom then
          local centerX, centerY = left + width * 0.5, bottom + height * 0.5
          local parentCenterX, parentCenterY = oLeft + oWidth * 0.5, oBottom + oHeight * 0.5
          local axisDistance = math.abs(centerX - parentCenterX) - math.abs(centerY - parentCenterY)
          local candidateLeft, candidateBottom
          if axisDistance >= 0 then
            candidateLeft = centerX < parentCenterX and (oLeft - gap - width) or (oRight + gap)
            candidateBottom = oTop - height
          else
            candidateLeft = oLeft
            candidateBottom = centerY < parentCenterY and (oBottom - gap - height) or (oTop + gap)
          end
          local approach = math.abs(centerX - parentCenterX) + math.abs(centerY - parentCenterY)
          if not dockParent or approach < dockDistance then
            dockDistance, dockLeft, dockBottom, dockParent = approach, candidateLeft, candidateBottom, other
          end
        end

        if rangesOverlap(bottom, top, oBottom, oTop, distance) then
          if math.abs(left - oLeft) <= distance then consider(oLeft, bottom, other) end
          if math.abs(left - oRight) <= distance then consider(oRight, bottom, other) end
          if math.abs(right - oLeft) <= distance then consider(oLeft - width, bottom, other) end
          if math.abs(right - oRight) <= distance then consider(oRight - width, bottom, other) end
        end
        if rangesOverlap(left, right, oLeft, oRight, distance) then
          if math.abs(bottom - oBottom) <= distance then consider(left, oBottom, other) end
          if math.abs(bottom - oTop) <= distance then consider(left, oTop, other) end
          if math.abs(top - oBottom) <= distance then consider(left, oBottom - height, other) end
          if math.abs(top - oTop) <= distance then consider(left, oTop - height, other) end
        end

        if math.abs(left - (oRight + gap)) <= distance then
          if math.abs(top - oTop) <= distance then consider(oRight + gap, oTop - height, other) end
          if math.abs(bottom - oBottom) <= distance then consider(oRight + gap, oBottom, other) end
        end
        if math.abs(right - (oLeft - gap)) <= distance then
          if math.abs(top - oTop) <= distance then consider(oLeft - gap - width, oTop - height, other) end
          if math.abs(bottom - oBottom) <= distance then consider(oLeft - gap - width, oBottom, other) end
        end
        if math.abs(bottom - (oTop + gap)) <= distance and math.abs(left - oLeft) <= distance then
          consider(oLeft, oTop + gap, other)
        end
        if math.abs(top - (oBottom - gap)) <= distance and math.abs(left - oLeft) <= distance then
          consider(oLeft, oBottom - gap - height, other)
        end
      end
    end
  end

  if dockParent then
    bestLeft, bestBottom, bestParent, bestDistance = dockLeft, dockBottom, dockParent, 0
  end

  if bestDistance <= distance then
    if bestParent and window.db.snapSize ~= false then
      local pScale = bestParent.frame.GetEffectiveScale and bestParent.frame:GetEffectiveScale() or 1
      if type(pScale) ~= "number" or pScale <= 0 then pScale = 1 end
      local parentWidth = bestParent.frame:GetWidth() * pScale
      local parentHeight = bestParent.frame:GetHeight() * pScale
      local parentLeft = bestParent.frame.GetLeft and bestParent.frame:GetLeft()
      local parentBottom = bestParent.frame.GetBottom and bestParent.frame:GetBottom()
      if parentWidth and parentHeight then
        -- Side-by-side docks share the vertical span: adopt the target's
        -- height and keep the width. Stacked docks share the horizontal
        -- span: adopt the width and keep the row count. Corner docks take
        -- both. Only recurse when a dimension truly changes, or a
        -- beside/stacked dock would loop forever on the axis it never
        -- touches.
        local newWidth, newHeight = width, height
        local changed = false
        local beside, stacked = false, false
        if parentLeft and parentBottom then
          parentLeft, parentBottom = parentLeft * pScale, parentBottom * pScale
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
  -- Keep the exact ratio instead of rounding to whole rows so ApplyLayout's
  -- rows * rowStep reconstruction reproduces this height precisely: snapSize
  -- copies the neighbour's raw pixel height, and rounding it here would
  -- unalign a snapped edge the moment the drag ends (a hidden-title window
  -- adopting a titled window's height cannot even represent the header delta
  -- in whole rows). The fractional final row is not dead space anymore:
  -- ApplyLayout paints it as a short trailing bar. Only the 3..30 clamp may
  -- change the height, and the SetHeight below settles that immediately
  -- rather than deferring it to the next rebuild.
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
