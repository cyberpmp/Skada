local env = _G or getfenv(0)
local Skada = env.Skada

-- Renderers for the settings dialog's control types. The options schema
-- (options.schema.lua) stays the data contract: each spec is a leaf of the
-- options table -- type, name, desc, get/set/values/sorting/func/disabled --
-- and every renderer turns one spec into one frame parented to the pane's
-- scroll child. The dialog (options.dialog.lua) owns placement; nothing
-- here reads a rendered rect: every frame is sized explicitly, so GetWidth
-- answers even before the first render pass.
--
-- Frames are pooled per parent and type. A renderer is three steps: `create`
-- builds the frame and its regions once, `bind` points an existing frame at
-- a spec (labels, geometry for the cell width, tooltip) and `refresh`
-- repaints it from the spec's current value and disabled state. Switching
-- pages rebinds pooled frames instead of creating new ones -- a frame on
-- this client is never released, so the old build-per-visit leaked a page
-- of frames every time the sidebar was clicked -- and every commit
-- refreshes the page's other controls so dependents (a color swatch behind
-- its toggle, size matching behind a window's snap toggle) dim and undim
-- live.
--
-- The controls wear the default UI's own art (ui.style.lua carries the
-- texture paths): the check box, the dropdown frame with its arrow, the
-- input-box border, the chat color swatch, the slider track and the red
-- panel button, with gold labels and white values from the client's font
-- objects -- so the dialog reads like one of the game's own option panels.
--
-- Two client quirk avoidances are designed in rather than shimmed:
--   * sliders have NO value EditBox -- the value lives in a plain FontString,
--     which cannot come up blank (preset EditBox text set before the first
--     render is the bug class this dialog exists to bury);
--   * the one remaining EditBox (window name) gets its preset text only after
--     a render pass has placed it, via the one-shot driver below.
local Controls = {}
Skada.OptionsControls = Controls

local SkadaCompat = env.SkadaCompat
local Common = Skada.Common
local Style = Skada.UIStyle

local table_getn = table.getn
local table_insert = table.insert
local table_remove = table.remove
local floor = math.floor
local min = math.min
local max = math.max
local tonumber = tonumber
local tostring = tostring
local type = type
local string_format = string.format
local setGoldFont = Style.SetGoldFont
local setWhiteFont = Style.SetWhiteFont
local setGameFont = Style.SetGameFont

-- Row height the dialog's layout engine reserves per control type.
Controls.HEIGHTS = {
  title = 40,
  header = 26,
  note = 20,
  toggle = 32,
  select = 40,
  color = 32,
  input = 36,
  range = 46,
  execute = 28,
}

-- How many of a type share one row of the pane. Types absent here always
-- take a full row (title, header, note, execute).
Controls.COLUMNS = {
  toggle = 3,
  color = 3,
  select = 3,
  input = 2,
  range = 3,
}

-- Only controls of one row kind share a row, so a row of check boxes lines
-- up as check boxes and a row of sliders as sliders. Toggles and color
-- swatches are the same shape (a glyph and a label) and mix freely.
Controls.ROW_KIND = {
  toggle = "inline",
  color = "inline",
  select = "select",
  input = "input",
  range = "range",
}

-- Framed controls (dropdown, input box, panel button) keep this much clear
-- of their cell's edges so neighbours in the grid never touch.
local CELL_INSET = 4
-- The gold caption row above a framed control.
local CAPTION_HEIGHT = 14
-- Where the text beside a check box or color swatch starts.
local ROW_TEXT_X = 30
-- A control whose spec says it does not apply right now.
local DISABLED_ALPHA = 0.45
Controls.DISABLED_ALPHA = DISABLED_ALPHA

-- The slider template's backdrop (OptionsSliderTemplate), which renders
-- correctly in game today.
local SLIDER_BACKDROP = {
  bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
  edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
  tile = true, tileSize = 8, edgeSize = 8,
  insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

local function bindTooltip(frame, spec)
  if spec.desc then
    Common.AttachTooltip(frame, spec.name, spec.desc)
  else
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
  end
end

local function isDisabled(spec)
  local disabled = spec and spec.disabled
  if type(disabled) == "function" then return disabled() and true or false end
  return disabled and true or false
end
Controls.IsDisabled = isDisabled

-- Called after every commit with the control that committed; the dialog
-- refreshes the page's other controls so dependents follow.
local commitListener
function Controls.SetCommitListener(listener) commitListener = listener end

local function notifyCommitted(control)
  if commitListener then commitListener(control) end
end

-- Every write a control makes goes through here, so the dialog can tell
-- its own commits from changes made elsewhere (which repaint the page
-- through the windowSettingsChanged bus event): the committing control
-- repaints the page itself, once, when it is done.
local committing = 0
function Controls.IsCommitting() return committing > 0 end

local function commitValue(spec, first, second, third)
  committing = committing + 1
  local ok, message = pcall(spec.set, first, second, third)
  committing = committing - 1
  if not ok then error(message, 0) end
end

-- The schema passes select choices either as an ordered {value=, label=}
-- table bound directly or as a function returning one (dynamic lists);
-- both spellings appear in options.schema.lua.
local function resolveValues(spec)
  if type(spec.values) == "function" then return spec.values() end
  return spec.values or {}
end

local function resolveSorting(spec)
  if type(spec.sorting) == "function" then return spec.sorting() end
  return spec.sorting or {}
end

-- The small gold caption above a dropdown or input box.
local function captionLabel(parent)
  local label = parent:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGoldFont(label, true)
  label:SetHeight(CAPTION_HEIGHT)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", CELL_INSET, 0)
  label:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CELL_INSET, 0)
  return label
end

-- Reserve two lines beside check boxes and color swatches. Explicit text
-- dimensions allow wrapping before the client resolves the frame's anchors.
local function rowLabel(button, height)
  local label = button:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  label:SetJustifyV("MIDDLE")
  setWhiteFont(label, false)
  label:SetHeight(height)
  if label.SetWordWrap then label:SetWordWrap(true) end
  if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end
  label:SetPoint("LEFT", button, "LEFT", ROW_TEXT_X, 0)
  return label
end

local function sizeRowLabel(label, width)
  label:SetWidth(max(1, width - ROW_TEXT_X - CELL_INSET))
end

-- Additive highlight art on a Button, the way the client's own templates
-- declare theirs. Without `region` the glow covers the whole button; with
-- one it is re-anchored to that region (the check box, say) at `size`.
local function applyHighlight(button, texturePath, region, size)
  button:SetHighlightTexture(texturePath)
  local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
  if not highlight then return end
  if highlight.SetBlendMode then highlight:SetBlendMode("ADD") end
  if region then
    highlight:ClearAllPoints()
    highlight:SetWidth(size)
    highlight:SetHeight(size)
    highlight:SetPoint("CENTER", region, "CENTER", 0, 0)
  end
end

local function paintDisabled(control)
  local disabled = isDisabled(control.spec)
  control.disabled = disabled
  control:SetAlpha(disabled and DISABLED_ALPHA or 1)
  return disabled
end

-- Whether a click may act: the spec is asked now, not the dimming last
-- painted, which a change made outside the dialog may have left stale
-- (and a stale dimming is corrected on the spot).
local function blocked(control)
  if not control.spec then return true end
  local disabled = isDisabled(control.spec)
  if disabled ~= control.disabled then paintDisabled(control) end
  return disabled
end

-- Root frame the select popup parents to (never the scroll child, which
-- clips). The dialog sets this before its first build.
local popupRoot
function Controls.SetPopupRoot(root) popupRoot = root end

function Controls.ClosePopup()
  if popupRoot and popupRoot.selectPopup then popupRoot.selectPopup:Hide() end
end

-- ---------------------------------------------------------------------------
-- The select popup: the default UI's dropdown list -- its dialog-box
-- backdrop and insets, the quest-log row highlight, a check mark beside the
-- current value -- as one reusable frame parented to the dialog root so the
-- scroll child's clipping can't cut it off, at DIALOG strata so it rides
-- above the HIGH dialog. Entries are plain Buttons (the only frame type the
-- client gives OnClick), pooled and re-labelled per open.
-- ---------------------------------------------------------------------------
local POPUP_ENTRY_HEIGHT = 20
local POPUP_INSET = 12
local POPUP_WIDTH = 170 + 2 * POPUP_INSET

local function ensureSelectPopup()
  local popup = popupRoot.selectPopup
  if popup then return popup end
  popup = CreateFrame("Frame", nil, popupRoot)
  popupRoot.selectPopup = popup
  popup:SetWidth(POPUP_WIDTH)
  -- Strata before any entries exist, so they inherit it at creation; this
  -- client never re-derives a child's layering after the fact.
  popup:SetFrameStrata("DIALOG")
  popup:EnableMouse(true)
  popup:SetBackdrop(Style.MENU_BACKDROP)
  popup.entries = {}
  popup:Hide()

  -- A screen-wide layer just under the open list: a click anywhere else
  -- (the dropdown itself included) lands here and closes the list, the
  -- way the default UI's menus close. It hangs off the dialog root, not
  -- the popup, so its level can sit below the popup's.
  local catcher = CreateFrame("Frame", nil, popupRoot)
  catcher:SetFrameStrata("DIALOG")
  catcher:SetAllPoints(UIParent)
  catcher:EnableMouse(true)
  catcher:SetScript("OnMouseDown", function() popup:Hide() end)
  catcher:Hide()
  popup.catcher = catcher
  popup:SetScript("OnHide", function() catcher:Hide() end)

  local function makeEntry()
    local entry = CreateFrame("Button", nil, popup)
    entry:SetWidth(POPUP_WIDTH - 2 * POPUP_INSET)
    entry:SetHeight(POPUP_ENTRY_HEIGHT)
    applyHighlight(entry, Style.ROW_HIGHLIGHT_TEXTURE)

    -- The check mark the default UI's lists put beside the current value.
    local marker = entry:CreateTexture(nil, "ARTWORK")
    marker:SetTexture(Style.CHECK_MARK_TEXTURE)
    marker:SetWidth(16)
    marker:SetHeight(16)
    marker:SetPoint("LEFT", entry, "LEFT", 0, 0)
    marker:Hide()
    entry.marker = marker

    local text = entry:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", entry, "LEFT", 18, 0)
    text:SetPoint("RIGHT", entry, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    setWhiteFont(text, true)
    entry.text = text

    -- activate is re-assigned each open with the entry's current value.
    entry:SetScript("OnClick", function()
      popup:Hide()
      if entry.activateValue ~= nil then entry.activate() end
    end)
    return entry
  end

  function popup:ShowChoices(anchorButton, spec, onChanged)
    local values = resolveValues(spec)
    local sorting = resolveSorting(spec)
    local current = spec.get()
    local choiceCount = table_getn(sorting)
    while table_getn(self.entries) < choiceCount do
      table_insert(self.entries, makeEntry())
    end
    local entryIndex, entry
    for entryIndex = 1, table_getn(self.entries) do
      entry = self.entries[entryIndex]
      if entryIndex <= choiceCount then
        local value = sorting[entryIndex]
        entry.activate = function()
          commitValue(spec, value)
          if onChanged then onChanged() end
        end
        entry.activateValue = value
        entry.text:SetText(values[value] or tostring(value))
        if value == current then entry.marker:Show() else entry.marker:Hide() end
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", self, "TOPLEFT", POPUP_INSET,
          -(POPUP_INSET + (entryIndex - 1) * POPUP_ENTRY_HEIGHT))
        entry:Show()
      else
        entry:Hide()
      end
    end
    self:SetHeight(2 * POPUP_INSET + choiceCount * POPUP_ENTRY_HEIGHT)
    self:ClearAllPoints()
    -- Hangs off the dropdown like the default UI's list: the border overlaps
    -- the dropdown's bottom edge and the entry text lines up with its text.
    self:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", -16, 6)
    self.catcher:Show()
    self:SetFrameLevel(self.catcher:GetFrameLevel() + 1)
    SkadaCompat.FixLevels(self)
    self:Show()
  end

  return popup
end

-- ---------------------------------------------------------------------------
-- Select: the default UI's dropdown (UIDropDownMenuTemplate's three slices
-- of CharacterCreate-LabelFrame, arrow button and white text) under a gold
-- caption. The whole cell is the clickable Button; the template's geometry
-- hangs the art 15 left and 17 right of the drawn box, so the slices reach
-- past the cell's inset edges by exactly that much.
-- ---------------------------------------------------------------------------
local Select = {}
-- A dropdown's shown value before its first label (nil is a real value).
local UNSHOWN = {}

function Select.create(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(Controls.HEIGHTS.select)

  button.caption = captionLabel(button)

  local left = button:CreateTexture(nil, "ARTWORK")
  left:SetTexture(Style.DROPDOWN_TEXTURE)
  left:SetTexCoord(0, 0.1953125, 0, 1)
  left:SetWidth(25)
  left:SetHeight(64)
  left:SetPoint("TOPLEFT", button, "TOPLEFT", CELL_INSET - 15, 3)

  local right = button:CreateTexture(nil, "ARTWORK")
  right:SetTexture(Style.DROPDOWN_TEXTURE)
  right:SetTexCoord(0.8046875, 1, 0, 1)
  right:SetWidth(25)
  right:SetHeight(64)
  right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 17 - CELL_INSET, 3)

  local middle = button:CreateTexture(nil, "ARTWORK")
  middle:SetTexture(Style.DROPDOWN_TEXTURE)
  middle:SetTexCoord(0.1953125, 0.8046875, 0, 1)
  middle:SetHeight(64)
  middle:SetPoint("LEFT", left, "RIGHT", 0, 0)
  middle:SetPoint("RIGHT", right, "LEFT", 0, 0)

  local label = button:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setWhiteFont(label, true)
  label:SetPoint("LEFT", left, "LEFT", 25, 2)
  label:SetPoint("RIGHT", right, "RIGHT", -43, 2)
  button.valueText = label

  local arrow = CreateFrame("Button", nil, button)
  arrow:SetWidth(24)
  arrow:SetHeight(24)
  arrow:SetPoint("TOPRIGHT", right, "TOPRIGHT", -16, -18)
  arrow:SetNormalTexture(Style.DROPDOWN_ARROW_TEXTURE)
  arrow:SetPushedTexture(Style.DROPDOWN_ARROW_PUSHED_TEXTURE)
  applyHighlight(arrow, Style.MOUSE_HIGHLIGHT_TEXTURE)

  local function open()
    if blocked(button) then return end
    ensureSelectPopup():ShowChoices(button, button.spec, function()
      -- A commit can rebuild the page (a rename does), handing this
      -- frame back to the pool; then the new page has painted itself.
      if not button.spec then return end
      Select.refresh(button)
      notifyCommitted(button)
    end)
  end
  button:SetScript("OnClick", open)
  arrow:SetScript("OnClick", open)
  return button
end

function Select.bind(button, spec, width)
  button:SetWidth(width)
  button.shownValue = UNSHOWN
  button.caption:SetText(spec.name)
  bindTooltip(button, spec)
end

-- Resolving the label builds the spec's whole choice list (every saved
-- fight, for Segment), so a repaint after a commit elsewhere on the page
-- keeps the label it has while the value is unchanged. `force` (a bind, or
-- a change made outside the dialog, which can relabel a saved fight under
-- the same index) always resolves.
function Select.refresh(button, force)
  local spec = button.spec
  local current = spec.get()
  if force or button.shownValue ~= current then
    local values = resolveValues(spec)
    button.valueText:SetText(values[current] or tostring(current))
    button.shownValue = current
  end
  paintDisabled(button)
end

-- ---------------------------------------------------------------------------
-- Toggle: the default UI's check box with its label to the right.
-- ---------------------------------------------------------------------------
local Toggle = {}

function Toggle.create(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(Controls.HEIGHTS.toggle)

  local box = button:CreateTexture(nil, "ARTWORK")
  box:SetTexture(Style.CHECK_BOX_TEXTURE)
  box:SetWidth(24)
  box:SetHeight(24)
  box:SetPoint("LEFT", button, "LEFT", 2, 0)
  applyHighlight(button, Style.CHECK_BOX_HIGHLIGHT_TEXTURE, box, 24)

  local check = button:CreateTexture(nil, "OVERLAY")
  check:SetTexture(Style.CHECK_MARK_TEXTURE)
  check:SetWidth(24)
  check:SetHeight(24)
  check:SetPoint("CENTER", box, "CENTER", 0, 0)
  button.checkMark = check

  button.label = rowLabel(button, Controls.HEIGHTS.toggle)

  button:SetScript("OnClick", function()
    if blocked(button) then return end
    local spec = button.spec
    commitValue(spec, not (spec.get() and true or false))
    if not button.spec then return end
    Toggle.refresh(button)
    notifyCommitted(button)
  end)
  return button
end

function Toggle.bind(button, spec, width)
  button:SetWidth(width)
  sizeRowLabel(button.label, width)
  button.label:SetText(spec.name)
  bindTooltip(button, spec)
end

function Toggle.refresh(button)
  if button.spec.get() then button.checkMark:Show() else button.checkMark:Hide() end
  paintDisabled(button)
end

-- ---------------------------------------------------------------------------
-- Range: the default UI's option slider: gold label and white value on one
-- line, the track below, its bounds in small white text at the ends.
-- ---------------------------------------------------------------------------
local Range = {}

local function formatRangeValue(spec, value)
  if spec.isPercent then
    return string_format("%d%%", floor((tonumber(value) or 0) * 100 + 0.5))
  end
  return string_format("%d", tonumber(value) or 0)
end

function Range.create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(Controls.HEIGHTS.range)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGoldFont(label, false)
  label:SetHeight(CAPTION_HEIGHT)
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET, 0)
  label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -60, 0)
  frame.label = label

  local valueText = frame:CreateFontString(nil, "OVERLAY")
  valueText:SetJustifyH("RIGHT")
  setWhiteFont(valueText, false)
  valueText:SetHeight(CAPTION_HEIGHT)
  valueText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CELL_INSET, 0)
  valueText:SetPoint("TOPLEFT", label, "TOPRIGHT", 0, 0)
  frame.valueText = valueText

  local slider = CreateFrame("Slider", nil, frame)
  slider:SetOrientation("HORIZONTAL")
  slider:SetHeight(15)
  slider:SetHitRectInsets(0, 0, -10, 0)
  slider:SetBackdrop(SLIDER_BACKDROP)
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET, -17)
  slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CELL_INSET, -17)
  frame.slider = slider

  local lowText = slider:CreateFontString(nil, "ARTWORK")
  lowText:SetJustifyH("LEFT")
  setWhiteFont(lowText, true)
  lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 3)
  lowText:SetHeight(13)
  frame.lowText = lowText

  local highText = slider:CreateFontString(nil, "ARTWORK")
  highText:SetJustifyH("RIGHT")
  setWhiteFont(highText, true)
  highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 3)
  highText:SetHeight(13)
  frame.highText = highText

  -- Dragging fires OnValueChanged continuously; every change goes straight
  -- to spec.set (the render loop already coalesces rebuilds at its update
  -- rate), and the plain-text label repaints with it. The page's other
  -- controls are refreshed once, when the drag ends, not per tick: that
  -- refresh asks every dropdown for its label. A spec marked
  -- commitOnRelease (Saved fights, whose setter deletes fights) only shows
  -- the value while dragging and commits the one it is released at, so a
  -- drag down and back up again loses nothing.
  slider:SetScript("OnValueChanged", function(self, newvalue)
    if rawget(slider, "setup") then return end
    local spec = frame.spec
    if not spec then return end
    -- Dimming painted before an outside change can leave the thumb live;
    -- put it back and repaint rather than write a disabled setting.
    if isDisabled(spec) then
      Range.refresh(frame)
      return
    end
    local rangeMin, rangeMax, rangeStep = frame.rangeMin, frame.rangeMax, frame.rangeStep
    local value = tonumber(newvalue) or (slider.GetValue and slider:GetValue()) or rangeMin
    local snapped = rangeMin + floor((value - rangeMin) / rangeStep + 0.5) * rangeStep
    if snapped > rangeMax then snapped = rangeMax elseif snapped < rangeMin then snapped = rangeMin end
    valueText:SetText(formatRangeValue(spec, snapped))
    if spec.commitOnRelease then
      frame.pendingValue = snapped
    else
      commitValue(spec, snapped)
    end
    frame.pendingNotify = true
  end)

  local function flushNotify()
    if not frame.pendingNotify then return end
    frame.pendingNotify = nil
    local pendingValue = frame.pendingValue
    frame.pendingValue = nil
    if not frame.spec then return end
    if pendingValue ~= nil then commitValue(frame.spec, pendingValue) end
    if frame.spec then notifyCommitted(frame) end
  end
  slider:SetScript("OnMouseUp", flushNotify)
  -- A drag the page took away (closed or switched mid-drag) still lands.
  slider:SetScript("OnHide", flushNotify)
  -- A rebuild of the same page hides the slider too, but the player has
  -- not let go: drop the value held so far instead of committing whatever
  -- the drag happens to be passing (a Saved fights trim would be final).
  -- A drag that carries on sets it again; the rebuilt page repaints the
  -- rest.
  frame.dropPending = function()
    frame.pendingValue = nil
    frame.pendingNotify = nil
  end

  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, wheelDelta)
    if blocked(frame) then return end
    local delta = Common.GetWheelDelta(wheelDelta)
    if delta == 0 then return end
    local value = tonumber(slider.GetValue and slider:GetValue()) or frame.rangeMin
    if delta > 0 then
      value = min(value + frame.rangeStep, frame.rangeMax)
    else
      value = max(value - frame.rangeStep, frame.rangeMin)
    end
    slider:SetValue(value)
    flushNotify()
  end)
  return frame
end

function Range.bind(frame, spec, width)
  frame:SetWidth(width)
  frame.pendingNotify, frame.pendingValue = nil, nil
  frame.label:SetText(spec.name)
  frame.rangeMin = spec.min or 0
  frame.rangeMax = spec.max or 100
  frame.rangeStep = spec.step or 1
  -- Programmatic range changes fire OnValueChanged on the real client; the
  -- setup flag silences the handler for this pass.
  rawset(frame.slider, "setup", true)
  frame.slider:SetMinMaxValues(frame.rangeMin, frame.rangeMax)
  frame.slider:SetValueStep(frame.rangeStep)
  rawset(frame.slider, "setup", nil)
  frame.lowText:SetText(formatRangeValue(spec, frame.rangeMin))
  frame.highText:SetText(formatRangeValue(spec, frame.rangeMax))
  -- On the slider: the cell frame takes no mouse, so it never sees OnEnter.
  bindTooltip(frame.slider, spec)
end

function Range.refresh(frame)
  local spec = frame.spec
  -- Mid-drag on a commit-on-release slider, the thumb's value is the truth.
  local current = frame.pendingValue or tonumber(spec.get()) or frame.rangeMin
  rawset(frame.slider, "setup", true)
  frame.slider:SetValue(current)
  rawset(frame.slider, "setup", nil)
  frame.valueText:SetText(formatRangeValue(spec, current))
  local disabled = paintDisabled(frame)
  frame.slider:EnableMouse(not disabled)
end

-- ---------------------------------------------------------------------------
-- Color: the default UI's chat color swatch (the swatch art tinted with the
-- value over a white square, as UIDropDownMenu draws its color rows) with
-- its label to the right.
-- ---------------------------------------------------------------------------
local Color = {}

function Color.create(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(Controls.HEIGHTS.color)

  local swatchBackground = button:CreateTexture(nil, "BACKGROUND")
  swatchBackground:SetTexture(Style.WHITE)
  swatchBackground:SetWidth(14)
  swatchBackground:SetHeight(14)
  swatchBackground:SetPoint("LEFT", button, "LEFT", 7, 0)

  local swatch = button:CreateTexture(nil, "ARTWORK")
  swatch:SetTexture(Style.COLOR_SWATCH_TEXTURE)
  swatch:SetWidth(16)
  swatch:SetHeight(16)
  swatch:SetPoint("CENTER", swatchBackground, "CENTER", 0, 0)
  applyHighlight(button, Style.MOUSE_HIGHLIGHT_TEXTURE, swatch, 20)
  button.swatch = swatch

  button.label = rowLabel(button, Controls.HEIGHTS.color)

  button:SetScript("OnClick", function()
    if blocked(button) or not ColorPickerFrame then return end
    local spec = button.spec
    local red, green, blue = spec.get()
    local previous = { red or 1, green or 1, blue or 1 }
    -- The picker is not modal: the page can change under it, and this
    -- pooled button may by then be bound to another color (or released).
    -- The pick still lands on the spec it was opened for; the swatch is
    -- repainted from whatever the button is bound to now, never from the
    -- picked color.
    -- The page repaint is for the page actually on screen: none once the
    -- dialog is closed, and the picker reports every drag step.
    local function repaintBound()
      if not button.spec or not button:IsShown() or not (popupRoot and popupRoot:IsShown()) then
        return
      end
      Color.refresh(button)
      notifyCommitted(button)
    end
    ColorPickerFrame.func = function()
      local pickedRed, pickedGreen, pickedBlue = ColorPickerFrame:GetColorRGB()
      commitValue(spec, pickedRed, pickedGreen, pickedBlue)
      repaintBound()
    end
    ColorPickerFrame.cancelFunc = function()
      commitValue(spec, previous[1], previous[2], previous[3])
      repaintBound()
    end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = previous
    ColorPickerFrame:SetColorRGB(previous[1], previous[2], previous[3])
    -- This client doesn't re-derive the shared picker's child layering when
    -- it is raised; the compat layer's OnShow hook carries strata/levels down
    -- (kept in core.compat.lua for BigDebuffs' picker too), and the level bump
    -- here puts it above this dialog's deepest frame.
    ColorPickerFrame:SetFrameStrata("DIALOG")
    ColorPickerFrame:SetFrameLevel((popupRoot:GetFrameLevel() or 0) + 50)
    SkadaCompat.FixLevels(ColorPickerFrame)
    ColorPickerFrame:Show()
  end)
  return button
end

-- The same shape as a toggle (a glyph and a label), bound the same way.
Color.bind = Toggle.bind

function Color.refresh(button)
  local red, green, blue = button.spec.get()
  button.swatch:SetVertexColor(red or 1, green or 1, blue or 1)
  paintDisabled(button)
end

-- ---------------------------------------------------------------------------
-- Execute: the default UI's red panel button. The button is the control
-- itself (so its OnClick is the control's); it sits inset in its row through
-- the cell offsets the dialog honours when placing it, and a full-width row
-- keeps it at a button's width rather than the pane's.
-- ---------------------------------------------------------------------------
local EXECUTE_MAX_WIDTH = 200

local Execute = {}

function Execute.create(parent)
  local button = Style:CreatePanelButton(parent, "", EXECUTE_MAX_WIDTH, 22)
  button.cellOffsetX = CELL_INSET
  button.cellOffsetY = 3
  button:SetScript("OnClick", function()
    if blocked(button) then return end
    button.spec.func()
  end)
  return button
end

function Execute.bind(button, spec, width)
  button:SetWidth(min(width - 2 * CELL_INSET, EXECUTE_MAX_WIDTH))
  button:SetText(spec.name)
  bindTooltip(button, spec)
end

function Execute.refresh(button)
  paintDisabled(button)
end

-- ---------------------------------------------------------------------------
-- The input display driver. Preset EditBox text set before a render pass has
-- placed the box comes up blank on this client (the scroll is worked out
-- against the not-yet-existing rect), so the box's value is queued here and
-- only applied once GetLeft() answers -- one pass, no settle logic, because
-- the dialog's arithmetic layout never re-flows. The driver is a plain Frame
-- because OnUpdate does not fire on EditBox frames here.
-- ---------------------------------------------------------------------------
local INPUT_DISPLAY_BUDGET = 300

local pendingInputDisplays = {}
local inputDriver

local function ensureInputDriver()
  if inputDriver then
    inputDriver:Show()
    return
  end
  inputDriver = CreateFrame("Frame", "SkadaOptionsInputDriver", popupRoot or UIParent)
  inputDriver:SetWidth(0.001)
  inputDriver:SetHeight(0.001)
  inputDriver:SetScript("OnUpdate", function() Controls.PumpInputDisplay() end)
  inputDriver:Show()
end

function Controls.QueueInputDisplay(box, text)
  pendingInputDisplays[box] = text
  rawset(box, "skadaDisplayFrames", 0)
  ensureInputDriver()
end

function Controls.ClearQueuedInputDisplays()
  local box
  for box in pairs(pendingInputDisplays) do
    rawset(box, "skadaDisplayFrames", nil)
    pendingInputDisplays[box] = nil
  end
end

-- One tick of the driver: apply the queued text to every box a render pass
-- has placed. Called from the driver's OnUpdate in game and by hand in the
-- test harness.
function Controls.PumpInputDisplay()
  local readyBoxes, readyTexts = {}, {}
  local box, text
  for box, text in pairs(pendingInputDisplays) do
    local frames = (rawget(box, "skadaDisplayFrames") or 0) + 1
    rawset(box, "skadaDisplayFrames", frames)
    local placed = box.GetLeft and box:GetLeft() ~= nil
    if placed or frames >= INPUT_DISPLAY_BUDGET then
      table_insert(readyBoxes, box)
      table_insert(readyTexts, text)
    end
  end
  local readyIndex
  for readyIndex = 1, table_getn(readyBoxes) do
    box = readyBoxes[readyIndex]
    text = readyTexts[readyIndex]
    pendingInputDisplays[box] = nil
    rawset(box, "skadaDisplayFrames", nil)
    rawset(box, "skadaDisplayText", text)
    -- A box the player is typing in keeps their text; the stored value
    -- only becomes its revert point.
    if not rawget(box, "skadaHasFocus") then
      box:SetText(text)
      box:ClearFocus()
    end
  end
  if inputDriver and not next(pendingInputDisplays) then inputDriver:Hide() end
end

-- ---------------------------------------------------------------------------
-- Input: the default UI's input box (InputBoxTemplate's border) under a gold
-- caption; the border's left cap hangs 5 outside the box, so the box starts
-- that much further in.
-- ---------------------------------------------------------------------------
local Input = {}

function Input.create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(Controls.HEIGHTS.input)

  frame.caption = captionLabel(frame)

  local box = CreateFrame("EditBox", nil, frame)
  box:SetHeight(20)
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET + 5, -16)
  box:SetAutoFocus(false)
  Style:ApplyInputBorder(box)
  frame.box = box

  -- Focus is tracked by hand (this client's EditBox has no HasFocus), so a
  -- page rebuild can tell a box the player is typing in from an idle one.
  box:SetScript("OnEditFocusGained", function() rawset(box, "skadaHasFocus", true) end)
  box:SetScript("OnEditFocusLost", function() rawset(box, "skadaHasFocus", nil) end)

  local function blur()
    rawset(box, "skadaHasFocus", nil)
    box:ClearFocus()
  end
  frame.blur = blur

  box:SetScript("OnEnterPressed", function()
    -- Released to the pool (its page was left while it held focus, so no
    -- setting is behind it any more) or disabled: nothing to commit.
    if blocked(frame) then
      blur()
      return
    end
    local typed = box:GetText()
    -- Enter on an unchanged name is not a rename: committing it would mark
    -- an auto-named window's title as custom for good.
    if typed ~= tostring(frame.spec.get() or "") then
      commitValue(frame.spec, typed)
    end
    blur()
    if not frame.spec then return end
    -- Show what was actually saved (a rejected value, say an empty name,
    -- puts the stored one back) and make it the revert point for Escape.
    -- The box is placed and focused here, so SetText is safe.
    local stored = tostring(frame.spec.get() or "")
    box:SetText(stored)
    rawset(box, "skadaDisplayText", stored)
    notifyCommitted(frame)
  end)
  box:SetScript("OnEscapePressed", function()
    box:SetText(rawget(box, "skadaDisplayText") or "")
    blur()
  end)
  return frame
end

function Input.bind(frame, spec, width)
  frame:SetWidth(width)
  frame.box:SetWidth(width - 2 * CELL_INSET - 5)
  frame.caption:SetText(spec.name)
  -- A box rebound to the option it was already showing while the player
  -- types (the same page rebuilt under them) keeps their text.
  local box = frame.box
  local typing = rawget(box, "skadaHasFocus") and frame.boundName == spec.name
  if not typing then
    if rawget(box, "skadaHasFocus") then frame.blur() end
    -- A reused box still shows the previous page's text until the driver
    -- applies the new value; blank it meanwhile. A fresh box is never
    -- SetText at build time (see the pump above).
    if rawget(box, "skadaDisplayText") ~= nil then
      box:SetText("")
      rawset(box, "skadaDisplayText", nil)
    end
  end
  frame.boundName = spec.name
  -- On the box: the cell frame takes no mouse, so it never sees OnEnter.
  bindTooltip(frame.box, spec)
end

function Input.refresh(frame)
  -- Never SetText directly: queue the value and let the driver apply it
  -- once the box has a real rect. A refresh while the value is unchanged
  -- must not clobber text the player is typing, so only requeue when the
  -- stored value differs from what was last displayed; while the box has
  -- focus a changed value only moves the revert point.
  local text = tostring(frame.spec.get() or "")
  local box = frame.box
  if rawget(box, "skadaHasFocus") then
    rawset(box, "skadaDisplayText", text)
  elseif rawget(box, "skadaDisplayText") ~= text then
    Controls.QueueInputDisplay(box, text)
  end
  paintDisabled(frame)
end

-- ---------------------------------------------------------------------------
-- Header: a gold heading at the left of the row with one muted hairline
-- trailing from its text to the right edge, in line with the page title
-- above it. The rule anchors to the label's own right edge, so nothing
-- measures the text.
-- ---------------------------------------------------------------------------
local Header = {}

function Header.create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(Controls.HEIGHTS.header)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGoldFont(label, false)
  -- One anchor only: the string sizes itself to its text, and the rule
  -- hangs off the right edge that gives it.
  label:SetPoint("LEFT", frame, "LEFT", CELL_INSET, 0)
  frame.label = label

  local rule = frame:CreateTexture(nil, "BACKGROUND")
  rule:SetTexture(Style.WHITE)
  rule:SetHeight(1)
  rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
  rule:SetPoint("RIGHT", frame, "RIGHT", -CELL_INSET, 0)
  rule:SetVertexColor(Style.RULE_R, Style.RULE_G, Style.RULE_B, Style.RULE_A)
  frame.rule = rule
  return frame
end

function Header.bind(frame, spec, width)
  frame:SetWidth(width)
  frame.label:SetText(spec.name)
end

function Header.refresh() end

-- ---------------------------------------------------------------------------
-- Title: the page's name in the large gold heading font with a muted
-- one-line description under it, the way the game's own option panels open.
-- ---------------------------------------------------------------------------
local Title = {}

function Title.create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(Controls.HEIGHTS.title)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGameFont(label, "GameFontNormalLarge", 16, Style.GOLD_R, Style.GOLD_G, Style.GOLD_B)
  label:SetHeight(20)
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET, -2)
  label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CELL_INSET, -2)
  frame.label = label

  local description = frame:CreateFontString(nil, "OVERLAY")
  description:SetJustifyH("LEFT")
  setGameFont(description, "GameFontHighlightSmall", 10, 0.8, 0.8, 0.8)
  description:SetHeight(14)
  description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
  description:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -2)
  frame.description = description
  return frame
end

function Title.bind(frame, spec, width)
  frame:SetWidth(width)
  -- A page with a title-row action (the dialog's Delete window button)
  -- keeps its name and description clear of that button.
  frame.label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(CELL_INSET + (spec.reserveRight or 0)), -2)
  frame.label:SetText(spec.name)
  frame.description:SetText(spec.desc or "")
end

function Title.refresh() end

-- ---------------------------------------------------------------------------
-- Note: one line of muted small text across the row.
-- ---------------------------------------------------------------------------
local Note = {}

local function createNoteText(frame)
  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGameFont(label, "GameFontHighlightSmall", 10, 0.8, 0.8, 0.8)
  label:SetHeight(Controls.HEIGHTS.note)
  label:SetPoint("LEFT", frame, "LEFT", CELL_INSET, 0)
  label:SetPoint("RIGHT", frame, "RIGHT", -CELL_INSET, 0)
  return label
end

function Note.create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(Controls.HEIGHTS.note)
  frame.label = createNoteText(frame)
  return frame
end

function Note.bind(frame, spec, width)
  frame:SetWidth(width)
  frame.label:SetText(spec.name)
end

function Note.refresh() end

-- ---------------------------------------------------------------------------
-- The pool and the public surface.
-- ---------------------------------------------------------------------------
local renderers = {
  toggle = Toggle,
  select = Select,
  range = Range,
  color = Color,
  execute = Execute,
  input = Input,
  header = Header,
  title = Title,
  note = Note,
}

-- Free frames by parent and type. Frames never move between parents (this
-- client does not re-derive layering on SetParent), so each parent keeps
-- its own pool.
local pools = {}

local function freeList(parent, controlType)
  local byType = pools[parent]
  if not byType then
    byType = {}
    pools[parent] = byType
  end
  local list = byType[controlType]
  if not list then
    list = {}
    byType[controlType] = list
  end
  return list
end

-- Binds a pooled (or freshly created) frame to `spec` at `width` and shows
-- it painted with the spec's current value. The frame carries `spec` as a
-- plain field so diagnostics and tests can tell which option it belongs to.
function Controls.Render(parent, spec, width)
  local renderer = renderers[spec.type]
  if not renderer then return nil end
  local free = freeList(parent, spec.type)
  local control = table_remove(free)
  if not control then
    control = renderer.create(parent)
    control.controlType = spec.type
    control.pool = free
  end
  control.spec = spec
  renderer.bind(control, spec, width)
  renderer.refresh(control)
  control:Show()
  return control
end

-- Hides a control and hands it back to its pool for the next page. An
-- input box gives up keyboard focus (a hidden box must not keep swallowing
-- keys) unless `keepFocus`: the same page is being rebuilt, and Input.bind
-- hands the player's typing back to the box when it lands on the same
-- option again. A slider held mid-drag drops its uncommitted value on such
-- a rebuild rather than committing it.
function Controls.Release(control, keepFocus)
  if control.blur and not keepFocus then control.blur() end
  if control.dropPending and keepFocus then control.dropPending() end
  control:Hide()
  control:ClearAllPoints()
  control.spec = nil
  if control.pool then table_insert(control.pool, control) end
end

-- Repaints one control from its spec's current value and disabled state.
-- `force` re-resolves what a control may cache (a dropdown's label).
function Controls.Refresh(control, force)
  local renderer = control.spec and renderers[control.spec.type]
  if renderer then renderer.refresh(control, force) end
end
