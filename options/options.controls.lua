local env = _G or getfenv(0)
local Skada = env.Skada

-- Renderers for the settings dialog's control types. The options schema
-- (options.schema.lua) stays the data contract: each spec is a leaf of the
-- options table -- type, name, desc, get/set/values/sorting/func -- and every
-- renderer turns one spec into one frame parented to the pane's scroll child.
-- The dialog (options.dialog.lua) owns placement; nothing here reads a
-- rendered rect: every frame is sized explicitly, so GetWidth answers even
-- before the first render pass.
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
local floor = math.floor
local min = math.min
local max = math.max
local tonumber = tonumber
local tostring = tostring
local string_format = string.format
local setGoldFont = Style.SetGoldFont
local setWhiteFont = Style.SetWhiteFont

-- Row height the dialog's layout engine reserves per control type.
Controls.HEIGHTS = {
  header = 24,
  toggle = 32,
  select = 40,
  color = 32,
  input = 36,
  range = 48,
  execute = 28,
}

-- Framed controls (dropdown, input box, panel button) keep this much clear
-- of their cell's edges so neighbours in the three-column grid never touch.
local CELL_INSET = 4
-- The gold caption row above a framed control.
local CAPTION_HEIGHT = 14
-- Where the text beside a check box or color swatch starts.
local ROW_TEXT_X = 30

-- The slider template's backdrop (OptionsSliderTemplate), which renders
-- correctly in game today.
local SLIDER_BACKDROP = {
  bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
  edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
  tile = true, tileSize = 8, edgeSize = 8,
  insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local function attachTooltip(frame, spec)
  if spec.desc then
    Common.AttachTooltip(frame, spec.name, spec.desc)
  end
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
local function captionLabel(parent, text)
  local label = parent:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGoldFont(label, true)
  label:SetText(text)
  label:SetHeight(CAPTION_HEIGHT)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", CELL_INSET, 0)
  label:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CELL_INSET, 0)
  return label
end

-- Reserve two lines beside check boxes and color swatches. Explicit text
-- dimensions allow wrapping before the client resolves the frame's anchors.
local function rowLabel(button, text, width, height)
  local label = button:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  label:SetJustifyV("MIDDLE")
  setWhiteFont(label, false)
  label:SetWidth(max(1, width - ROW_TEXT_X - CELL_INSET))
  label:SetHeight(height)
  if label.SetWordWrap then label:SetWordWrap(true) end
  if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end
  label:SetText(text)
  label:SetPoint("LEFT", button, "LEFT", ROW_TEXT_X, 0)
  return label
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

-- Root frame the select popup parents to (never the scroll child, which
-- clips). The dialog sets this before its first build.
local popupRoot
function Controls.SetPopupRoot(root) popupRoot = root end

function Controls.ClosePopup()
  if popupRoot and popupRoot.selectPopup then popupRoot.selectPopup:Hide() end
end

-- The select popup: the default UI's dropdown list -- its dialog-box
-- backdrop and insets, the quest-log row highlight, a check mark beside the
-- current value -- as one reusable frame parented to the dialog root so the
-- scroll child's clipping can't cut it off, at DIALOG strata so it rides
-- above the HIGH dialog. Entries are plain Buttons (the only frame type the
-- client gives OnClick), pooled and re-labelled per open.
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
    entry:SetScript("OnClick", function(self)
      popup:Hide()
      if self.activateValue ~= nil then self.activate() end
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
          spec.set({}, value)
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
    SkadaCompat.FixLevels(self)
    self:Show()
  end

  return popup
end

-- A select is the default UI's dropdown (UIDropDownMenuTemplate's three
-- slices of CharacterCreate-LabelFrame, arrow button and white text) under
-- a gold caption. The whole cell is the clickable Button; the template's
-- geometry hangs the art 15 left and 17 right of the drawn box, so the
-- slices reach past the cell's inset edges by exactly that much.
local function renderSelect(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
  button:SetHeight(40)

  captionLabel(button, spec.name)

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

  local arrow = CreateFrame("Button", nil, button)
  arrow:SetWidth(24)
  arrow:SetHeight(24)
  arrow:SetPoint("TOPRIGHT", right, "TOPRIGHT", -16, -18)
  arrow:SetNormalTexture(Style.DROPDOWN_ARROW_TEXTURE)
  arrow:SetPushedTexture(Style.DROPDOWN_ARROW_PUSHED_TEXTURE)
  applyHighlight(arrow, Style.MOUSE_HIGHLIGHT_TEXTURE)

  local function paint()
    local values = resolveValues(spec)
    local current = spec.get()
    label:SetText(values[current] or tostring(current))
  end
  button.valueText = label
  paint()

  local function open()
    ensureSelectPopup():ShowChoices(button, spec, paint)
  end
  button:SetScript("OnClick", open)
  arrow:SetScript("OnClick", open)
  attachTooltip(button, spec)
  return button
end

-- A toggle is the default UI's check box with its label to the right.
local function renderToggle(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
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

  rowLabel(button, spec.name, width, Controls.HEIGHTS.toggle)

  local function paint()
    if spec.get() then check:Show() else check:Hide() end
  end
  paint()
  button.checkMark = check

  button:SetScript("OnClick", function()
    spec.set({}, not (spec.get() and true or false))
    paint()
  end)
  attachTooltip(button, spec)
  return button
end

local function formatRangeValue(spec, value)
  if spec.isPercent then
    return string_format("%d%%", floor((tonumber(value) or 0) * 100 + 0.5))
  end
  return string_format("%d", tonumber(value) or 0)
end

-- A range is the default UI's option slider: gold label and white value on
-- one line, the track below, its bounds in small white text at the ends.
local function renderRange(parent, spec, width)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(width)
  frame:SetHeight(48)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setGoldFont(label, false)
  label:SetText(spec.name)
  label:SetHeight(CAPTION_HEIGHT)
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET, 0)
  label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -60, 0)

  local valueText = frame:CreateFontString(nil, "OVERLAY")
  valueText:SetJustifyH("RIGHT")
  setWhiteFont(valueText, false)
  valueText:SetHeight(CAPTION_HEIGHT)
  valueText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CELL_INSET, 0)
  valueText:SetPoint("TOPLEFT", label, "TOPRIGHT", 0, 0)

  local rangeMin = spec.min or 0
  local rangeMax = spec.max or 100
  local rangeStep = spec.step or 1

  local slider = CreateFrame("Slider", nil, frame)
  slider:SetOrientation("HORIZONTAL")
  slider:SetHeight(15)
  slider:SetHitRectInsets(0, 0, -10, 0)
  slider:SetBackdrop(SLIDER_BACKDROP)
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET, -17)
  slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CELL_INSET, -17)
  slider:SetMinMaxValues(rangeMin, rangeMax)
  slider:SetValueStep(rangeStep)

  local lowText = slider:CreateFontString(nil, "ARTWORK")
  lowText:SetJustifyH("LEFT")
  setWhiteFont(lowText, true)
  lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 3)
  lowText:SetHeight(13)
  lowText:SetText(formatRangeValue(spec, rangeMin))

  local highText = slider:CreateFontString(nil, "ARTWORK")
  highText:SetJustifyH("RIGHT")
  setWhiteFont(highText, true)
  highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 3)
  highText:SetHeight(13)
  highText:SetText(formatRangeValue(spec, rangeMax))

  -- Dragging fires OnValueChanged continuously; every change goes straight
  -- to spec.set (the render loop already coalesces rebuilds at its update
  -- rate), and the plain-text label repaints with it.
  slider:SetScript("OnValueChanged", function(self, newvalue)
    if rawget(self, "setup") then return end
    local value = tonumber(newvalue) or (self.GetValue and self:GetValue()) or rangeMin
    local snapped = rangeMin + floor((value - rangeMin) / rangeStep + 0.5) * rangeStep
    if snapped > rangeMax then snapped = rangeMax elseif snapped < rangeMin then snapped = rangeMin end
    valueText:SetText(formatRangeValue(spec, snapped))
    spec.set({}, snapped)
  end)

  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, wheelDelta)
    local delta = Common.GetWheelDelta(wheelDelta)
    if delta == 0 then return end
    local value = tonumber(self.GetValue and self:GetValue()) or rangeMin
    if delta > 0 then
      value = min(value + rangeStep, rangeMax)
    else
      value = max(value - rangeStep, rangeMin)
    end
    self:SetValue(value)
  end)

  local function paint()
    local current = tonumber(spec.get()) or rangeMin
    -- Programmatic SetValue would fire OnValueChanged back into spec.set;
    -- the setup flag silences the handler for this pass, exactly as the
    -- working vendored slider does.
    rawset(slider, "setup", true)
    slider:SetValue(current)
    rawset(slider, "setup", nil)
    valueText:SetText(formatRangeValue(spec, current))
  end
  paint()

  -- Test/inspection handles (plain frame fields, not closures).
  frame.slider = slider
  frame.valueText = valueText

  attachTooltip(frame, spec)
  return frame
end

-- A color is the default UI's chat color swatch (the swatch art tinted with
-- the value over a white square, as UIDropDownMenu draws its color rows)
-- with its label to the right.
local function renderColor(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
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

  rowLabel(button, spec.name, width, Controls.HEIGHTS.color)

  local function paint()
    local red, green, blue = spec.get()
    swatch:SetVertexColor(red or 1, green or 1, blue or 1)
  end
  paint()

  button:SetScript("OnClick", function()
    if not ColorPickerFrame then return end
    local red, green, blue = spec.get()
    local previous = { red or 1, green or 1, blue or 1 }
    ColorPickerFrame.func = function()
      local pickedRed, pickedGreen, pickedBlue = ColorPickerFrame:GetColorRGB()
      spec.set({}, pickedRed, pickedGreen, pickedBlue)
      swatch:SetVertexColor(pickedRed, pickedGreen, pickedBlue)
    end
    ColorPickerFrame.cancelFunc = function()
      spec.set({}, previous[1], previous[2], previous[3])
      swatch:SetVertexColor(previous[1], previous[2], previous[3])
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
  attachTooltip(button, spec)
  return button
end

-- An execute is the default UI's red panel button. The button is the
-- control itself (so its OnClick is the control's); it sits inset in its
-- row through the cell offsets the dialog honours when placing it, and a
-- full-width row keeps it at a button's width rather than the pane's.
local EXECUTE_MAX_WIDTH = 200

local function renderExecute(parent, spec, width)
  local button = Style:CreatePanelButton(parent, spec.name,
    min(width - 2 * CELL_INSET, EXECUTE_MAX_WIDTH), 22)
  button.cellOffsetX = CELL_INSET
  button.cellOffsetY = 3
  button:SetScript("OnClick", function() spec.func({}) end)
  attachTooltip(button, spec)
  return button
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
    box:SetText(text)
    box:ClearFocus()
  end
  if inputDriver and not next(pendingInputDisplays) then inputDriver:Hide() end
end

-- An input is the default UI's input box (InputBoxTemplate's border) under
-- a gold caption; the border's left cap hangs 5 outside the box, so the box
-- starts that much further in.
local function renderInput(parent, spec, width)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(width)
  frame:SetHeight(36)

  captionLabel(frame, spec.name)

  local box = CreateFrame("EditBox", nil, frame)
  box:SetWidth(width - 2 * CELL_INSET - 5)
  box:SetHeight(20)
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_INSET + 5, -16)
  box:SetAutoFocus(false)
  Style:ApplyInputBorder(box)

  -- Never SetText at build time: queue the value and let the driver apply it
  -- once the box has a real rect (see the pump above).
  Controls.QueueInputDisplay(box, tostring(spec.get() or ""))

  box:SetScript("OnEnterPressed", function(self)
    spec.set({}, self:GetText())
    -- The committed value becomes the revert point, so a later Escape puts
    -- back what is actually saved, not a stale preset.
    rawset(self, "skadaDisplayText", self:GetText())
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText(rawget(self, "skadaDisplayText") or "")
    self:ClearFocus()
  end)

  -- Test/inspection handle.
  frame.box = box

  attachTooltip(frame, spec)
  return frame
end

-- A header is the classic centered gold heading with a tooltip-border line
-- running out to each edge. The lines anchor to the label's own edges, so
-- nothing measures the text.
local function renderHeader(parent, spec, width)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(width)
  frame:SetHeight(24)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("CENTER")
  setGoldFont(label, false)
  label:SetText(spec.name)
  -- One anchor only: the string sizes itself to its text, and the lines
  -- below hang off the edges that gives it.
  label:SetPoint("CENTER", frame, "CENTER", 0, 0)

  local leftLine = frame:CreateTexture(nil, "BACKGROUND")
  leftLine:SetTexture(Style.HEADING_LINE_TEXTURE)
  leftLine:SetTexCoord(0.81, 0.94, 0.5, 1)
  leftLine:SetHeight(8)
  leftLine:SetPoint("LEFT", frame, "LEFT", CELL_INSET, 0)
  leftLine:SetPoint("RIGHT", label, "LEFT", -5, 0)

  local rightLine = frame:CreateTexture(nil, "BACKGROUND")
  rightLine:SetTexture(Style.HEADING_LINE_TEXTURE)
  rightLine:SetTexCoord(0.81, 0.94, 0.5, 1)
  rightLine:SetHeight(8)
  rightLine:SetPoint("RIGHT", frame, "RIGHT", -CELL_INSET, 0)
  rightLine:SetPoint("LEFT", label, "RIGHT", 5, 0)
  return frame
end

local renderers = {
  toggle = renderToggle,
  select = renderSelect,
  range = renderRange,
  color = renderColor,
  execute = renderExecute,
  input = renderInput,
  header = renderHeader,
}

function Controls.Render(parent, spec, width)
  local renderer = renderers[spec.type]
  if not renderer then return nil end
  local control = renderer(parent, spec, width)
  -- Kept on the frame (a plain field, safe on real frames and stubs alike)
  -- so diagnostics and tests can tell which option a control belongs to.
  if control then control.spec = spec end
  return control
end
