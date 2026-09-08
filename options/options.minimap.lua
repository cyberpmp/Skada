local Skada = (_G or getfenv(0)).Skada

local MinimapButton = {}
Skada.MinimapButton = MinimapButton

local Common = Skada.Common
local getClickButton = Common.GetClickButton
local attachTooltip = Common.AttachTooltip

local cos = math.cos
local sin = math.sin
local deg = math.deg
local rad = math.rad
local atan2 = math.atan2 or math.atan
local abs = math.abs

-- 78px is the conventional "flush against the minimap circle" radius most
-- Ace2/LibDBIcon-era minimap buttons use (SuperAPI's FuBarPlugin-based icon
-- included, at 80px) -- the ring texture below is drawn to sit right against
-- that edge, so pushing the radius out from here leaves a visible gap
-- between the button and the minimap (reported in game). The button
-- collision this radius was once bumped out to dodge (see CHANGELOG 2.0.2)
-- turned out to be a real bug elsewhere -- other addons' icons going
-- missing, not a genuine overlap risk -- so there is nothing left to dodge.
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
  instance:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- Same construction every other minimap button on this client uses
  -- (SuperAPI's FuBarPlugin-based icon included): the icon texture on its
  -- own BACKGROUND layer, sized and inset like a normal square icon, with
  -- the client's own circular tracking-border ring drawn as a separate,
  -- larger OVERLAY texture on top of it -- the ring's artwork already
  -- carries the round frame and shadow, so it (not a backdrop) is what
  -- makes the button read as "a minimap button" instead of a bare icon.
  local icon = instance:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\Spell_Nature_Lightning")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", instance, "TOPLEFT", 7, -5)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

  local ring = instance:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetWidth(53)
  ring:SetHeight(53)
  ring:SetPoint("TOPLEFT", instance, "TOPLEFT")

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

  attachTooltip(instance, "Skada",
    "Left-click to show or hide the meter window.\nRight-click to open the settings window.\nShift-click to reset fight data. Drag to reposition.")

  positionAt(instance, Skada.db.profile.minimap.angle)
  if Skada.db.profile.minimap.show == false then instance:Hide() end
  return instance
end
