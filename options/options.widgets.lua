local Skada = (_G or getfenv(0)).Skada

local OptionsWidgets = {}
Skada.OptionsWidgets = OptionsWidgets

local Common = Skada.Common
local Style = Skada.UIStyle

local floor = math.floor
local max = math.max
local min = math.min
local tonumber = tonumber
local tostring = tostring
local type = type
local table_getn = table.getn

local trackBackdrop = Common.TRACK_BACKDROP

local SLIDER_BACKDROP = Style.FLAT_BACKDROP

local HIGHLIGHT_COLOR = { Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B }
local CONTROL_R, CONTROL_G, CONTROL_B = Style.SURFACE_R, Style.SURFACE_G, Style.SURFACE_B
local CONTROL_HOVER_R, CONTROL_HOVER_G, CONTROL_HOVER_B = 0.095, 0.103, 0.126
local BORDER_R, BORDER_G, BORDER_B = 0.12, 0.13, 0.16
local MUTED_R, MUTED_G, MUTED_B = Style.MUTED_R, Style.MUTED_G, Style.MUTED_B

local UI_FONT = "Fonts\\FRIZQT__.TTF"
if GameFontNormal and GameFontNormal.GetFont then
  local path = GameFontNormal:GetFont()
  if type(path) == "string" then UI_FONT = path end
end

local function setUiFont(fontString, size)
  fontString:SetFont(UI_FONT, size)
end

local DEFAULT_ROW_WIDTH = 384

local PAD_X = 8

local NATIVE_MENU = UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton and ToggleDropDownMenu

local dropdownCount = 0

function OptionsWidgets.AttachTooltip(button, title, description)
  button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine(title, 1, 1, 1)
    GameTooltip:AddLine(description, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function OptionsWidgets.CursorToUnits(frame)
  local scale
  if frame.GetEffectiveScale then
    local effective = frame:GetEffectiveScale()
    if type(effective) == "number" and effective > 0 then scale = effective end
  end
  if not scale then
    local parentScale = UIParent.GetScale and UIParent:GetScale()
    if type(parentScale) == "number" and parentScale > 0 then scale = parentScale end
  end
  if not scale or scale <= 0 then scale = 1 end
  return scale
end

function OptionsWidgets.CreateKit(controls, rowWidth)
  local ROW_WIDTH = rowWidth or DEFAULT_ROW_WIDTH
  local kit = {}

  local function registerControl(row, refresh)
    row.refresh = refresh
    controls[table_getn(controls) + 1] = row
  end

  function kit.createRow(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(ROW_WIDTH)
    row:SetHeight(height or 22)
    return row
  end

  function kit.createCaption(row, text, width)
    local caption = row:CreateFontString(nil, "OVERLAY")
    caption:SetPoint("LEFT", row, "LEFT", 2, 0)
    caption:SetJustifyH("LEFT")
    setUiFont(caption, 12)
    caption:SetText(text)
    if width then caption:SetWidth(width) end
    return caption
  end

  local checkCount = 0

  function kit.createCheckbox(parent, label, description, get, set)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row:SetWidth(ROW_WIDTH)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 30

    -- Standard game checkbox (same template FastHeal's settings use) so the
    -- checked state is unmistakable. Mouse stays off it: the row button owns
    -- clicks, so the whole row toggles and shows the tooltip.
    checkCount = checkCount + 1
    local cb = CreateFrame("CheckButton", "SkadaOptionsCheck" .. checkCount, row, "OptionsCheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 1)
    cb:EnableMouse(false)

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetJustifyH("LEFT")
    setUiFont(text, 12)
    text:SetText(label)

    row:SetScript("OnClick", function()
      PlaySound("igMainMenuCheckBox")
      set(not get())
      row.refresh()
      GameTooltip:Hide()
    end)
    OptionsWidgets.AttachTooltip(row, label, description)
    row.label = label

    function row.setValue(value)
      set(value)
      row.refresh()
    end

    function row.refresh()
      cb:SetChecked(get() and true or false)
    end
    registerControl(row, row.refresh)
    return row
  end

  function kit.createSlider(parent, label, description, minValue, maxValue, step, format, get, set)
    local row = kit.createRow(parent, 44)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 58

    row:EnableMouse(true)

    local caption = row:CreateFontString(nil, "OVERLAY")
    caption:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
    caption:SetJustifyH("LEFT")
    setUiFont(caption, 12)
    caption:SetText(label)

    local valueText = row:CreateFontString(nil, "OVERLAY")
    valueText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -3)
    valueText:SetJustifyH("RIGHT")
    setUiFont(valueText, 12)
    -- Gold value, mirroring the standard options slider so the live number
    -- reads at a glance.
    valueText:SetTextColor(1, 0.82, 0, 1)

    local track = CreateFrame("Button", nil, row)
    track:RegisterForClicks("LeftButtonUp")
    track:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -23)
    track:SetWidth(ROW_WIDTH - 4)
    track:SetHeight(8)
    track:SetBackdrop(SLIDER_BACKDROP)
    track:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
    track:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(Style.WHITE)
    thumb:SetVertexColor(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], 1)
    thumb:SetWidth(6)
    thumb:SetHeight(12)

    local lowText = row:CreateFontString(nil, "OVERLAY")
    lowText:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, 1)
    lowText:SetJustifyH("LEFT")
    setUiFont(lowText, 10)
    lowText:SetTextColor(MUTED_R, MUTED_G, MUTED_B, 1)
    lowText:SetText(format and format(minValue) or tostring(minValue))

    local highText = row:CreateFontString(nil, "OVERLAY")
    highText:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, 1)
    highText:SetJustifyH("RIGHT")
    setUiFont(highText, 10)
    highText:SetTextColor(MUTED_R, MUTED_G, MUTED_B, 1)
    highText:SetText(format and format(maxValue) or tostring(maxValue))

    local function quantize(value)
      value = min(maxValue, max(minValue, value))
      value = minValue + floor((value - minValue) / step + 0.5) * step
      return min(maxValue, max(minValue, value))
    end

    local function cursorToUnits(cursorX)
      return cursorX / OptionsWidgets.CursorToUnits(track)
    end

    local warnedGeometry = false
    local function setFromCursor()
      if not GetCursorPosition then return end
      local left = track:GetLeft()
      local width = track:GetWidth()
      if not left or not width or width <= 0 then
        if not warnedGeometry then
          warnedGeometry = true
          Skada:Print(label .. " slider: track geometry unreadable (left=" ..
            tostring(left) .. ", width=" .. tostring(width) .. "); drag skipped.")
        end
        return
      end
      local rawX = GetCursorPosition()
      if type(rawX) ~= "number" then return end
      set(quantize(minValue + (maxValue - minValue) * ((cursorToUnits(rawX) - left) / width)))
      row.refresh()
    end

    local dragging = false
    local function startDrag()
      dragging = true
      setFromCursor()
    end
    local function stopDrag() dragging = false end

    track:SetScript("OnMouseDown", startDrag)
    track:SetScript("OnMouseUp", stopDrag)
    row:SetScript("OnMouseDown", startDrag)
    row:SetScript("OnMouseUp", stopDrag)

    if IsMouseButtonDown and track.IsMouseOver then
      local buttonWasDown = false
      row:SetScript("OnUpdate", function()
        local down = IsMouseButtonDown("LeftButton") and true or false
        if dragging then
          if down and track:IsMouseOver() then
            setFromCursor()
          elseif not down then
            dragging = false
          end
        elseif down and not buttonWasDown and track:IsMouseOver() then
          dragging = true
          setFromCursor()
        end
        buttonWasDown = down
      end)
    end

    track:SetScript("OnClick", function() setFromCursor() end)
    OptionsWidgets.AttachTooltip(track, label, description)

    row.label = label
    row.track = track

    function row.refresh()
      local value = tonumber(get()) or minValue
      local span = maxValue - minValue
      local ratio = span > 0 and (value - minValue) / span or 0
      ratio = min(1, max(0, ratio))
      local trackWidth = track:GetWidth() or (ROW_WIDTH - 4)
      thumb:ClearAllPoints()
      thumb:SetPoint("CENTER", track, "LEFT", 4 + ratio * (trackWidth - 8), 0)
      valueText:SetText(format(value))
    end
    registerControl(row, row.refresh)
    return row
  end

  function kit.createDropdown(parent, label, description, choices, get, set)
    local row = kit.createRow(parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 28

    kit.createCaption(row, label)

    local function resolveChoices()
      if type(choices) == "function" then return choices() end
      return choices
    end

    local valueText
    local menuFrame

    local function labelFor(value)
      local list = resolveChoices()
      local i
      for i = 1, table_getn(list) do
        if list[i].value == value then return list[i].label end
      end
    end

    function row.applyChoice(value)
      set(value)
      row.refresh()
      Skada:MarkDirty()
    end

    local function initializer(frame, level)
      local list = resolveChoices()
      local current = get()
      local i
      for i = 1, table_getn(list) do
        local choice = list[i]
        local info = UIDropDownMenu_CreateInfo()
        info.text = choice.label
        info.value = choice.value
        info.checked = choice.value == current
        info.func = function()
          row.applyChoice(choice.value)
          if CloseDropDownMenus then CloseDropDownMenus() end
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end

    local function ensureMenu()
      if menuFrame or not NATIVE_MENU then return end
      dropdownCount = dropdownCount + 1
      menuFrame = CreateFrame("Frame", "SkadaOptionsDropDown" .. dropdownCount, UIParent, "UIDropDownMenuTemplate")
      row.menuFrame = menuFrame
      UIDropDownMenu_Initialize(menuFrame, initializer)
    end

    local function cycle(delta)
      local list = resolveChoices()
      local current = get()
      local index = 0
      local i
      for i = 1, table_getn(list) do
        if list[i].value == current then index = i end
      end
      index = index + delta
      if index > table_getn(list) then index = 1 elseif index < 1 then index = table_getn(list) end
      row.applyChoice(list[index].value)
    end

    if NATIVE_MENU then
      local chrome = CreateFrame("Button", nil, row)
      chrome:RegisterForClicks("LeftButtonUp")
      chrome:SetPoint("RIGHT", row, "RIGHT", -2, 0)
      chrome:SetWidth(150)
      chrome:SetHeight(22)
      chrome:SetBackdrop(trackBackdrop)
      chrome:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
      chrome:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)

      valueText = chrome:CreateFontString(nil, "OVERLAY")
      valueText:SetPoint("LEFT", chrome, "LEFT", 8, 0)
      valueText:SetJustifyH("LEFT")
      setUiFont(valueText, 12)

      local arrow = chrome:CreateFontString(nil, "OVERLAY")
      arrow:SetPoint("RIGHT", chrome, "RIGHT", -7, 1)
      setUiFont(arrow, 10)
      arrow:SetText("v")
      arrow:SetTextColor(MUTED_R, MUTED_G, MUTED_B, 1)

      chrome:SetScript("OnClick", function()
        ensureMenu()
        if menuFrame then ToggleDropDownMenu(1, nil, menuFrame, chrome, 0, 0) end
      end)
      OptionsWidgets.AttachTooltip(chrome, label, description)
      row.chrome = chrome
    else
      valueText = row:CreateFontString(nil, "OVERLAY")
      valueText:SetPoint("RIGHT", row, "RIGHT", -20, 0)
      valueText:SetJustifyH("RIGHT")
      setUiFont(valueText, 12)

      local left = CreateFrame("Button", nil, row)
      left:SetPoint("RIGHT", row, "RIGHT", -18, 0)
      left:SetWidth(16)
      left:SetHeight(18)
      left:SetBackdrop(trackBackdrop)
      left:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
      left:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
      left.text = left:CreateFontString(nil, "OVERLAY")
      left.text:SetAllPoints(left)
      setUiFont(left.text, 11)
      left.text:SetText("<")
      left:SetScript("OnClick", function() cycle(-1) end)

      local right = CreateFrame("Button", nil, row)
      right:SetPoint("RIGHT", row, "RIGHT", -2, 0)
      right:SetWidth(16)
      right:SetHeight(18)
      right:SetBackdrop(trackBackdrop)
      right:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
      right:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
      right.text = right:CreateFontString(nil, "OVERLAY")
      right.text:SetAllPoints(right)
      setUiFont(right.text, 11)
      right.text:SetText(">")
      right:SetScript("OnClick", function() cycle(1) end)

      row.leftButton = left
      row.rightButton = right
      OptionsWidgets.AttachTooltip(row, label, description)
    end

    row.menuFrame = nil
    function row.refresh()
      local current = get()
      valueText:SetText(labelFor(current) or tostring(current))
      if menuFrame and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(menuFrame, current)
      end
    end
    registerControl(row, row.refresh)
    return row
  end

  function kit.createEditbox(parent, label, description, get, set)
    local row = kit.createRow(parent, 28)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 36

    kit.createCaption(row, label)

    local box = CreateFrame("EditBox", nil, row)
    box:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    box:SetWidth(180)
    box:SetHeight(20)
    box:SetBackdrop(trackBackdrop)
    box:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
    box:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
    box:SetTextInsets(6, 6, 0, 0)
    if box.SetFontObject then box:SetFontObject("GameFontHighlightSmall") end
    box:SetAutoFocus(false)

    box:SetScript("OnEnterPressed", function()
      box:ClearFocus()
      local text = box:GetText()
      if text and text ~= "" then set(text) end
      row.refresh()
      Skada:MarkDirty()
    end)
    box:SetScript("OnEscapePressed", function()
      box:ClearFocus()
      row.refresh()
    end)
    if box.SetScript then
      box:SetScript("OnEditFocusGained", function() box:HighlightText() end)
    end

    row.label = label
    row.editbox = box

    function row.setValue(value)
      set(value)
      row.refresh()
    end

    function row.refresh()
      box:SetText(tostring(get() or ""))
    end
    registerControl(row, row.refresh)
    return row
  end

  function kit.createSelector(parent, label, description, choices, get, set)
    local row = kit.createRow(parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 28

    kit.createCaption(row, label)

    local valueText = row:CreateFontString(nil, "OVERLAY")
    valueText:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    valueText:SetJustifyH("RIGHT")
    setUiFont(valueText, 12)

    local function currentIndex()
      local current = get()
      local i
      for i = 1, table_getn(choices) do
        if choices[i].value == current then return i end
      end
    end

    local function cycle(delta)
      local index = currentIndex() or (delta > 0 and 0 or table_getn(choices) + 1)
      index = index + delta
      if index > table_getn(choices) then index = 1 elseif index < 1 then index = table_getn(choices) end
      set(choices[index].value)
      row.refresh()
    end

    local left = CreateFrame("Button", nil, row)
    left:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    left:SetWidth(16)
    left:SetHeight(18)
    left:SetBackdrop(trackBackdrop)
    left:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
    left:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
    left.text = left:CreateFontString(nil, "OVERLAY")
    left.text:SetAllPoints(left)
    setUiFont(left.text, 11)
    left.text:SetText("<")
    left:SetScript("OnClick", function() cycle(-1) end)

    local right = CreateFrame("Button", nil, row)
    right:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    right:SetWidth(16)
    right:SetHeight(18)
    right:SetBackdrop(trackBackdrop)
    right:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 1)
    right:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
    right.text = right:CreateFontString(nil, "OVERLAY")
    right.text:SetAllPoints(right)
    setUiFont(right.text, 11)
    right.text:SetText(">")
    right:SetScript("OnClick", function() cycle(1) end)

    row.leftButton = left
    row.rightButton = right

    OptionsWidgets.AttachTooltip(row, label, description)

    function row.refresh()
      local index = currentIndex()
      valueText:SetText(index and choices[index].label or tostring(get()))
    end
    registerControl(row, row.refresh)
    return row
  end

  function kit.createSwatch(parent, label, description, get, set)
    local row = kit.createRow(parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 28

    kit.createCaption(row, label)

    local swatch = CreateFrame("Button", nil, row)
    swatch:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    swatch:SetWidth(26)
    swatch:SetHeight(14)
    swatch:SetBackdrop(trackBackdrop)
    swatch:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)

    swatch:SetScript("OnClick", function()
      if not ColorPickerFrame then
        Skada:Print("This client does not expose the color picker.")
        return
      end
      local current = get()
      ColorPickerFrame.previousValues = { r = current[1], g = current[2], b = current[3] }
      ColorPickerFrame.func = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        set(r, g, b)
        row.refresh()
        Skada:MarkDirty()
      end
      ColorPickerFrame.cancelFunc = function(previous)
        if previous then
          set(previous.r, previous.g, previous.b)
          row.refresh()
          Skada:MarkDirty()
        end
      end
      ColorPickerFrame:SetColorRGB(current[1], current[2], current[3])
      ShowUIPanel(ColorPickerFrame)
    end)
    OptionsWidgets.AttachTooltip(swatch, label, description)

    function row.refresh()
      local current = get()
      swatch:SetBackdropColor(current[1], current[2], current[3], 1)
    end
    registerControl(row, row.refresh)
    return row
  end

  function kit.createSectionHeader(parent, text)
    local row = kit.createRow(parent, 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 30
    local header = row:CreateFontString(nil, "OVERLAY")
    header:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    header:SetJustifyH("LEFT")
    setUiFont(header, 12)
    header:SetTextColor(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], 1)
    header:SetText(text)
    local rule = row:CreateTexture(nil, "BACKGROUND")
    rule:SetTexture(1, 1, 1)
    rule:SetAlpha(0.10)
    rule:SetWidth(ROW_WIDTH)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    return row
  end

  function kit.createInlineGroup(parent, title)
    local box = CreateFrame("Frame", nil, parent)
    box:SetWidth(ROW_WIDTH)
    box:SetBackdrop(trackBackdrop)
    box:SetBackdropColor(0.038, 0.042, 0.054, 0.92)
    box:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)

    local heading = box:CreateFontString(nil, "OVERLAY")
    heading:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -6)
    heading:SetJustifyH("LEFT")
    setUiFont(heading, 12)
    heading:SetTextColor(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], 1)
    heading:SetText(title)

    local content = CreateFrame("Frame", nil, box)
    content:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -24)
    content:SetWidth(ROW_WIDTH - 20)
    content.nextY = 0
    box.content = content
    return box
  end

  function kit.endInlineGroup(parent, box)
    local height = box.content.nextY + 36
    box:SetHeight(height)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + height + 10
    return box
  end

  function kit.createTabStrip(parent, tabs)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(30)
    strip.tabs = tabs

    local buttons = {}
    local selectedKey = nil
    local offset = 0

    local function applySelection(key)
      selectedKey = key
      local i, button
      for i = 1, table_getn(tabs) do
        button = buttons[i]
        if tabs[i].key == key then
          button.text:SetTextColor(1, 1, 1, 1)
          button:SetBackdropColor(0, 0, 0, 0)
          button:SetBackdropBorderColor(0, 0, 0, 0)
          button.marker:Show()
          button:SetFrameLevel(strip:GetFrameLevel() + 1)
          button.selected = true
        else
          button.text:SetTextColor(0.64, 0.67, 0.73, 1)
          button:SetBackdropColor(0, 0, 0, 0)
          button:SetBackdropBorderColor(0, 0, 0, 0)
          button.marker:Hide()
          button:SetFrameLevel(strip:GetFrameLevel())
          button.selected = false
        end
      end
      if strip.OnChange then strip.OnChange(key) end
    end

    local i
    for i = 1, table_getn(tabs) do
      local spec = tabs[i]
      local button = CreateFrame("Button", nil, strip)
      button:RegisterForClicks("LeftButtonUp")
      local width = max(72, (spec.label and (spec.label:len() * 7) or 40) + 24)
      button:SetWidth(width)
      button:SetHeight(22)
      button:SetPoint("TOPLEFT", strip, "TOPLEFT", offset, 0)
      offset = offset + width + 4
      button:SetBackdrop(Style.FLAT_BACKDROP)
      button:SetBackdropColor(0, 0, 0, 0)
      button:SetBackdropBorderColor(0, 0, 0, 0)

      button.marker = button:CreateTexture(nil, "ARTWORK")
      button.marker:SetTexture(Style.WHITE)
      button.marker:SetVertexColor(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], 1)
      button.marker:SetHeight(2)
      button.marker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 3, 2)
      button.marker:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 2)
      button.marker:Hide()

      button.text = button:CreateFontString(nil, "OVERLAY")
      button.text:SetAllPoints(button)
      button.text:SetJustifyH("CENTER")
      setUiFont(button.text, 12)
      button.text:SetText(spec.label)

      button:SetScript("OnClick", function() applySelection(spec.key) end)
      button:SetScript("OnEnter", function()
        if not button.selected then
          button.text:SetTextColor(0.88, 0.90, 0.94, 1)
        end
      end)
      button:SetScript("OnLeave", function()
        if not button.selected then
          button.text:SetTextColor(0.64, 0.67, 0.73, 1)
        end
      end)
      buttons[i] = button
    end

    function strip.SetSelected(self, key)
      applySelection(key)
    end
    function strip.GetSelected()
      return selectedKey
    end
    return strip
  end

  function kit.createScrollbar(parent, viewport, onScroll)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(10)
    bar:SetHeight(viewport:GetHeight())

    local track = CreateFrame("Button", nil, bar)
    track:RegisterForClicks("LeftButtonUp")
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    track:SetWidth(6)
    track:SetBackdrop(trackBackdrop)
    track:SetBackdropColor(0.055, 0.060, 0.073, 0.58)
    track:SetBackdropBorderColor(0, 0, 0, 0)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(6)
    thumb:SetHitRectInsets(-3, -3, 0, 0)
    thumb:SetBackdrop(trackBackdrop)
    thumb:SetBackdropColor(0.34, 0.38, 0.46, 0.90)
    thumb:SetBackdropBorderColor(0, 0, 0, 0)
    thumb:SetScript("OnEnter", function()
      thumb:SetBackdropColor(0.48, 0.53, 0.63, 0.96)
    end)
    thumb:SetScript("OnLeave", function()
      thumb:SetBackdropColor(0.34, 0.38, 0.46, 0.90)
    end)

    bar.track = track
    bar.thumb = thumb

    function bar.SetRange(self, contentHeight, viewHeight)
      self.contentHeight = contentHeight
      self.viewHeight = viewHeight
      self.maxOffset = max(0, contentHeight - viewHeight)
    end

    function bar.Update(self, offset)
      self.offset = offset
      local maxOffset = self.maxOffset or 0
      local trackHeight = track:GetHeight() or 100
      if maxOffset <= 0 or self.viewHeight <= 0 or self.contentHeight <= 0 then
        thumb:Hide()
        return
      end
      local ratio = min(1, max(0, offset / maxOffset))
      local thumbHeight = max(28, trackHeight * self.viewHeight / self.contentHeight)
      thumb:SetHeight(thumbHeight)
      thumb:ClearAllPoints()
      thumb:SetPoint("TOP", track, "TOP", 0, -(trackHeight - thumbHeight) * ratio)
      thumb:Show()
    end

    track:SetScript("OnClick", function()
      if not GetCursorPosition or not bar.maxOffset or bar.maxOffset <= 0 then return end
      local trackHeight = track:GetHeight() or 100
      local cursorX, cursorY = GetCursorPosition()
      if type(cursorY) ~= "number" then return end
      local top = track:GetTop()
      if type(top) ~= "number" then return end
      local units = cursorY / OptionsWidgets.CursorToUnits(track)
      local ratio = min(1, max(0, (top - units) / trackHeight))
      onScroll(ratio * bar.maxOffset)
    end)

    local dragging, grabOffset = false, 0
    local function stopDrag()
      dragging = false
      bar:SetScript("OnUpdate", nil)
    end
    local function updateDrag()
      if not dragging or not GetCursorPosition then return end
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        stopDrag()
        return
      end
      local cursorX, cursorY = GetCursorPosition()
      local trackTop = track:GetTop()
      local trackHeight = track:GetHeight()
      local thumbHeight = thumb:GetHeight()
      if type(cursorY) ~= "number" or type(trackTop) ~= "number" or
          type(trackHeight) ~= "number" or type(thumbHeight) ~= "number" then return end
      local units = cursorY / OptionsWidgets.CursorToUnits(track)
      local travel = max(1, trackHeight - thumbHeight)
      local position = trackTop - (units + grabOffset)
      onScroll(min(1, max(0, position / travel)) * (bar.maxOffset or 0))
    end
    thumb:SetScript("OnMouseDown", function()
      if not GetCursorPosition then return end
      local cursorX, cursorY = GetCursorPosition()
      local thumbTop = thumb:GetTop()
      if type(cursorY) ~= "number" or type(thumbTop) ~= "number" then return end
      grabOffset = thumbTop - cursorY / OptionsWidgets.CursorToUnits(thumb)
      dragging = true
      bar:SetScript("OnUpdate", updateDrag)
    end)
    thumb:SetScript("OnMouseUp", stopDrag)

    return bar
  end

  function kit.createActionButton(parent, label, description, onClick, width)
    local button = CreateFrame("Button", nil, parent)
    button:RegisterForClicks("LeftButtonUp")
    button:SetWidth(width or ROW_WIDTH)
    button:SetHeight(24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -parent.nextY)
    parent.nextY = parent.nextY + 32
    button:SetBackdrop(Style.FLAT_BACKDROP)
    button:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 0.88)
    button:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)

    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetJustifyH("CENTER")
    setUiFont(button.text, 12)
    button.text:SetText(label)

    button:SetScript("OnEnter", function()
      button:SetBackdropColor(CONTROL_HOVER_R, CONTROL_HOVER_G, CONTROL_HOVER_B, 0.96)
      button:SetBackdropBorderColor(HIGHLIGHT_COLOR[1], HIGHLIGHT_COLOR[2], HIGHLIGHT_COLOR[3], 0.62)
      GameTooltip:SetOwner(button, "ANCHOR_LEFT")
      GameTooltip:AddLine(label, 1, 1, 1)
      GameTooltip:AddLine(description, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
      button:SetBackdropColor(CONTROL_R, CONTROL_G, CONTROL_B, 0.88)
      button:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 1)
      GameTooltip:Hide()
    end)
    button:SetScript("OnClick", onClick)
    return button
  end

  return kit
end
