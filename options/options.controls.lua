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
local setUiFont = Style.SetUIFont

-- Row height the dialog's layout engine reserves per control type.
Controls.HEIGHTS = {
  header = 24,
  toggle = 24,
  select = 24,
  color = 24,
  input = 36,
  range = 48,
  execute = 28,
}

local CHECK_BOX_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_MARK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"
local EXPAND_ARROW_TEXTURE = "Interface\\ChatFrame\\ChatFrameExpandArrow"

-- The vendored slider's backdrop, which renders correctly in game today.
local SLIDER_BACKDROP = {
  bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
  edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
  tile = true, tileSize = 8, edgeSize = 8,
  insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local EDITBOX_BACKDROP = {
  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
  tile = true, edgeSize = 1, tileSize = 5,
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

local function goldLabel(parent, text)
  local label = parent:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setUiFont(label, 12)
  label:SetText(text)
  label:SetTextColor(Style.GOLD_R, Style.GOLD_G, Style.GOLD_B, 1)
  return label
end

local function buttonLabel(button, text)
  local label = button:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setUiFont(label, 11)
  label:SetText(text)
  label:SetTextColor(0.84, 0.86, 0.90, 1)
  return label
end

-- Root frame the select popup parents to (never the scroll child, which
-- clips). The dialog sets this before its first build.
local popupRoot
function Controls.SetPopupRoot(root) popupRoot = root end

function Controls.ClosePopup()
  if popupRoot and popupRoot.selectPopup then popupRoot.selectPopup:Hide() end
end

-- The select popup: one reusable menu frame modeled on
-- Report:CreateActionMenu (ui/ui.report.lua), parented to the dialog root so
-- the scroll child's clipping can't cut it off, at DIALOG strata so it rides
-- above the HIGH dialog. Entries are plain Buttons (the only frame type the
-- client gives OnClick), pooled and re-labelled per open.
local POPUP_ENTRY_HEIGHT = 20

local function ensureSelectPopup()
  local popup = popupRoot.selectPopup
  if popup then return popup end
  popup = CreateFrame("Frame", nil, popupRoot)
  popupRoot.selectPopup = popup
  popup:SetWidth(170)
  -- Strata before any entries exist, so they inherit it at creation; this
  -- client never re-derives a child's layering after the fact.
  popup:SetFrameStrata("DIALOG")
  popup:EnableMouse(true)
  Style:ApplyFlatFrame(popup, 0.985, 0.16, 0.18, 0.23)
  popup.entries = {}
  popup:Hide()

  local function makeEntry(entryIndex)
    local entry = CreateFrame("Button", nil, popup)
    entry:SetHeight(POPUP_ENTRY_HEIGHT)

    local highlight = entry:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints(entry)
    highlight:SetTexture(Style.WHITE)
    highlight:SetVertexColor(1, 1, 1, 0.075)
    highlight:Hide()
    entry.highlight = highlight

    local marker = entry:CreateTexture(nil, "ARTWORK")
    marker:SetTexture(Style.WHITE)
    marker:SetVertexColor(Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B, 0.92)
    marker:SetWidth(2)
    marker:SetPoint("TOPLEFT", entry, "TOPLEFT", 1, -3)
    marker:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 1, 3)
    marker:Hide()
    entry.marker = marker

    local text = entry:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", entry, "LEFT", 7, 0)
    text:SetPoint("RIGHT", entry, "RIGHT", -7, 0)
    text:SetJustifyH("LEFT")
    setUiFont(text, 11)
    entry.text = text

    -- activate is re-assigned each open with the entry's current value.
    entry:SetScript("OnClick", function(self)
      popup:Hide()
      if self.activateValue ~= nil then self.activate() end
    end)
    entry:SetScript("OnEnter", function(self)
      self.highlight:Show()
      self.text:SetTextColor(0.98, 0.98, 1, 1)
    end)
    entry:SetScript("OnLeave", function(self)
      self.highlight:Hide()
      self.text:SetTextColor(0.84, 0.86, 0.90, 1)
    end)
    return entry
  end

  function popup:ShowChoices(anchorButton, spec)
    local values = resolveValues(spec)
    local sorting = resolveSorting(spec)
    local current = spec.get()
    local choiceCount = table_getn(sorting)
    while table_getn(self.entries) < choiceCount do
      table_insert(self.entries, makeEntry(table_getn(self.entries) + 1))
    end
    local entryIndex, entry
    for entryIndex = 1, table_getn(self.entries) do
      entry = self.entries[entryIndex]
      if entryIndex <= choiceCount then
        local value = sorting[entryIndex]
        entry.activate = function() spec.set({}, value) end
        entry.activateValue = value
        entry.text:SetText(values[value] or tostring(value))
        entry.text:SetTextColor(0.84, 0.86, 0.90, 1)
        if value == current then entry.marker:Show() else entry.marker:Hide() end
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -(4 + (entryIndex - 1) * POPUP_ENTRY_HEIGHT))
        entry:Show()
      else
        entry:Hide()
      end
    end
    self:SetHeight(8 + choiceCount * POPUP_ENTRY_HEIGHT)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -4)
    SkadaCompat.FixLevels(self)
    self:Show()
  end

  return popup
end

local function renderSelect(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
  button:SetHeight(22)
  Style:ApplyButton(button)

  local label = buttonLabel(button, "")
  label:SetPoint("LEFT", button, "LEFT", 8, 0)
  label:SetPoint("RIGHT", button, "RIGHT", -24, 0)

  local arrow = button:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture(EXPAND_ARROW_TEXTURE)
  arrow:SetWidth(14)
  arrow:SetHeight(14)
  arrow:SetPoint("RIGHT", button, "RIGHT", -5, 0)

  local function paint()
    local values = resolveValues(spec)
    local current = spec.get()
    label:SetText(values[current] or tostring(current))
  end
  paint()

  button:SetScript("OnClick", function()
    ensureSelectPopup():ShowChoices(button, spec)
  end)
  attachTooltip(button, spec)
  return button
end

local function renderToggle(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
  button:SetHeight(22)
  Style:ApplyButton(button)

  local label = buttonLabel(button, spec.name)
  label:SetPoint("LEFT", button, "LEFT", 8, 0)
  label:SetPoint("RIGHT", button, "RIGHT", -26, 0)

  local box = button:CreateTexture(nil, "OVERLAY")
  box:SetTexture(CHECK_BOX_TEXTURE)
  box:SetWidth(14)
  box:SetHeight(14)
  box:SetPoint("RIGHT", button, "RIGHT", -6, 0)

  local check = button:CreateTexture(nil, "OVERLAY")
  check:SetTexture(CHECK_MARK_TEXTURE)
  check:SetWidth(12)
  check:SetHeight(12)
  check:SetPoint("CENTER", box, "CENTER", 0, 0)

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

local function renderRange(parent, spec, width)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(width)
  frame:SetHeight(48)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("CENTER")
  setUiFont(label, 12)
  label:SetText(spec.name)
  label:SetTextColor(Style.GOLD_R, Style.GOLD_G, Style.GOLD_B, 1)
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  label:SetHeight(14)

  local rangeMin = spec.min or 0
  local rangeMax = spec.max or 100
  local rangeStep = spec.step or 1

  local slider = CreateFrame("Slider", nil, frame)
  slider:SetOrientation("HORIZONTAL")
  slider:SetHeight(15)
  slider:SetHitRectInsets(0, 0, -10, 0)
  slider:SetBackdrop(SLIDER_BACKDROP)
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -17)
  slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -17)
  slider:SetMinMaxValues(rangeMin, rangeMax)
  slider:SetValueStep(rangeStep)

  local valueText = slider:CreateFontString(nil, "ARTWORK")
  valueText:SetJustifyH("CENTER")
  setUiFont(valueText, 11)
  valueText:SetPoint("TOP", slider, "BOTTOM", 0, 3)
  valueText:SetHeight(13)

  local lowText = slider:CreateFontString(nil, "ARTWORK")
  lowText:SetJustifyH("LEFT")
  setUiFont(lowText, 10)
  lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 3)
  lowText:SetHeight(13)
  lowText:SetText(formatRangeValue(spec, rangeMin))

  local highText = slider:CreateFontString(nil, "ARTWORK")
  highText:SetJustifyH("RIGHT")
  setUiFont(highText, 10)
  highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 3)
  highText:SetHeight(13)
  highText:SetText(formatRangeValue(spec, rangeMax))

  -- Value text sits centered; shift it clear of the corner labels on the
  -- two narrow ranges (0..8, 0..20) where the min/max texts would collide.
  if (rangeMax - rangeMin) <= 20 then
    valueText:ClearAllPoints()
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 16)
    lowText:Hide()
    highText:Hide()
  end

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

local function renderColor(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
  button:SetHeight(22)
  Style:ApplyButton(button)

  local label = buttonLabel(button, spec.name)
  label:SetPoint("LEFT", button, "LEFT", 8, 0)
  label:SetPoint("RIGHT", button, "RIGHT", -30, 0)

  local swatch = button:CreateTexture(nil, "OVERLAY")
  swatch:SetTexture(Style.WHITE)
  swatch:SetWidth(14)
  swatch:SetHeight(14)
  swatch:SetPoint("RIGHT", button, "RIGHT", -7, 0)

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

local function renderExecute(parent, spec, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
  button:SetHeight(26)
  Style:ApplyButton(button)

  local label = button:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("CENTER")
  setUiFont(label, 12)
  label:SetText(spec.name)
  label:SetTextColor(1, 0.48, 0.38, 1)
  label:SetAllPoints(button)

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

local function renderInput(parent, spec, width)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(width)
  frame:SetHeight(36)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setUiFont(label, 12)
  label:SetText(spec.name)
  label:SetTextColor(Style.GOLD_R, Style.GOLD_G, Style.GOLD_B, 1)
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  label:SetHeight(13)

  local box = CreateFrame("EditBox", nil, frame)
  box:SetWidth(width)
  box:SetHeight(19)
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -16)
  box:SetAutoFocus(false)
  box:SetTextInsets(5, 5, 0, 0)
  box:SetBackdrop(EDITBOX_BACKDROP)
  box:SetBackdropColor(0.055, 0.060, 0.075, 1)
  box:SetBackdropBorderColor(0.12, 0.13, 0.16, 1)
  box:SetTextColor(1, 1, 1, 1)
  setUiFont(box, 12)

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

local function renderHeader(parent, spec, width)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(width)
  frame:SetHeight(24)

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetJustifyH("LEFT")
  setUiFont(label, 13)
  label:SetText(spec.name)
  label:SetTextColor(Style.GOLD_R, Style.GOLD_G, Style.GOLD_B, 1)
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -4)
  label:SetHeight(14)

  local rule = frame:CreateTexture(nil, "BACKGROUND")
  rule:SetTexture(Style.WHITE)
  rule:SetVertexColor(0.28, 0.31, 0.38, 0.42)
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 4)
  rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 4)
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