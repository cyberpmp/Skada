local Skada = (_G or getfenv(0)).Skada

local MinimapButton = {}
Skada.MinimapButton = MinimapButton

local Common = Skada.Common
local getClickButton = Common.GetClickButton
local setFont = Common.SetFont

local cos = math.cos
local sin = math.sin
local deg = math.deg
local rad = math.rad
local atan2 = math.atan2 or math.atan
local abs = math.abs

local MINIMAP_RADIUS = 78

local button

local function positionAt(buttonFrame, angleDegrees)
  local angle = rad(angleDegrees or 205)
  buttonFrame:SetPoint("CENTER", Minimap, "CENTER",
    cos(angle) * MINIMAP_RADIUS, sin(angle) * MINIMAP_RADIUS)
end

function MinimapButton:Create()
  if button then return button end

  local instance = CreateFrame("Button", "SkadaMinimapButton", Minimap)
  button = instance
  instance:SetFrameStrata("MEDIUM")
  instance:SetWidth(31)
  instance:SetHeight(31)
  instance:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Minimap\\MiniMap-TrackingBorder",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  instance:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

  local label = instance:CreateFontString(nil, "OVERLAY")
  label:SetAllPoints(instance)
  setFont(label, 16)
  label:SetText("S")
  label:SetTextColor(1, 0.6, 0.15, 1)

  instance:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local dragging = false
  local moved = false
  local pressX, pressY

  instance:SetScript("OnMouseDown", function()
    dragging = true
    moved = false
    pressX, pressY = nil
    if GetCursorPosition and UIParent.GetScale then
      local cursorX, cursorY = GetCursorPosition()
      local scale = UIParent:GetScale() or 1
      if cursorX and scale > 0 then
        pressX, pressY = cursorX / scale, cursorY / scale
      end
    end
  end)
  instance:SetScript("OnMouseUp", function() dragging = false end)
  instance:SetScript("OnUpdate", function()
    if not dragging then return end
    if not GetCursorPosition or not UIParent.GetScale or not Minimap.GetCenter then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetScale() or 1
    if not cursorX or scale <= 0 then return end
    cursorX, cursorY = cursorX / scale, cursorY / scale
    if pressX and abs(cursorX - pressX) < 4 and abs(cursorY - pressY) < 4 then
      return
    end
    local mx, my = Minimap:GetCenter()
    if not mx or not my then return end
    moved = true
    Skada.db.profile.minimap.angle = deg(atan2(cursorY - my, cursorX - mx))
    positionAt(instance, Skada.db.profile.minimap.angle)
  end)

  instance:SetScript("OnClick", function(_, clickButton)
    clickButton = getClickButton(clickButton)
    local wasDrag = moved
    moved = false
    if wasDrag then return end
    if clickButton == "RightButton" then
      Skada.Options:Toggle()
      return
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
      local window = Skada.UI:GetPrimary()
      if window then window:ShowResetPopup() end
      return
    end
    local window = Skada.UI:GetActive()
    if not window then return end
    window.db.visible = not window.db.visible
    if window.db.visible then window.frame:Show() else window.frame:Hide() end
    window.layoutDirty = true
    Skada.UI:SyncLegacy(window)
    Skada:MarkDirty()
  end)

  Skada.OptionsWidgets.AttachTooltip(instance, "Skada",
    "Left-click to show or hide the meter window.\nRight-click to open the settings window.\nShift-click to reset fight data. Drag to reposition.")

  positionAt(instance, Skada.db.profile.minimap.angle)
  if Skada.db.profile.minimap.show == false then instance:Hide() end
  return instance
end
