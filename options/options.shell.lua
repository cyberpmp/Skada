local Skada = (_G or getfenv(0)).Skada

local Shell = {}
Skada.OptionsShell = Shell

local Common = Skada.Common
local getWheelDelta = Common.GetWheelDelta
local Style = Skada.UIStyle

local max = math.max
local min = math.min
local string_upper = string.upper
local table_getn = table.getn

local attachTooltip = Skada.OptionsWidgets.AttachTooltip

local VIEW_HEIGHT = 440
local CONTENT_WIDTH = 400
local TREE_WIDTH = 175
local NODE_HEIGHT = 24

local PAGE_DESCRIPTIONS = {
  general = "Core behavior and everyday conveniences.",
  data = "History, formatting, logging, and reset behavior.",
  window = "Appearance, navigation, and behavior for this window.",
}

local FRAME_BACKDROP = Style.FLAT_BACKDROP
local PANE_BACKDROP = Style.FLAT_BACKDROP

local UI_FONT = "Fonts\\FRIZQT__.TTF"
if GameFontNormal and GameFontNormal.GetFont then
  local path = GameFontNormal:GetFont()
  if type(path) == "string" then UI_FONT = path end
end

local function setUiFont(fontString, size)
  fontString:SetFont(UI_FONT, size)
end

function Shell.Build(owner)
  local frame = CreateFrame("Frame", "SkadaSettingsFrame", UIParent)
  frame:SetWidth(630)
  frame:SetHeight(500)
  frame:SetFrameStrata("MEDIUM")
  frame:SetBackdrop(FRAME_BACKDROP)
  frame:SetBackdropColor(0.026, 0.029, 0.037, 0.99)
  frame:SetBackdropBorderColor(0.095, 0.105, 0.13, 1)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetClampedToScreen(true)
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  Style:ApplyShadow(frame, true)
  if UISpecialFrames then
    UISpecialFrames[table_getn(UISpecialFrames) + 1] = "SkadaSettingsFrame"
  end

  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetWidth(570)
  titleBar:SetHeight(28)
  titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -6)

  local title = titleBar:CreateFontString(nil, "OVERLAY")
  title:SetPoint("LEFT", titleBar, "LEFT", 0, 1)
  setUiFont(title, 14)
  title:SetText("SKADA")
  title:SetTextColor(0.92, 0.93, 0.96, 1)

  local subtitle = titleBar:CreateFontString(nil, "OVERLAY")
  subtitle:SetPoint("LEFT", title, "RIGHT", 9, 0)
  setUiFont(subtitle, 11)
  subtitle:SetText("Meter settings")
  subtitle:SetTextColor(Style.MUTED_R, Style.MUTED_G, Style.MUTED_B, 1)

  local headerRule = frame:CreateTexture(nil, "ARTWORK")
  headerRule:SetTexture(Style.WHITE)
  headerRule:SetVertexColor(0.18, 0.20, 0.25, 0.48)
  headerRule:SetHeight(1)
  headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -38)
  headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -38)

  local close = CreateFrame("Button", nil, frame)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  close:SetWidth(18)
  close:SetHeight(18)
  Style:ApplyButton(close)
  close.text = close:CreateFontString(nil, "OVERLAY")
  close.text:SetAllPoints(close)
  setUiFont(close.text, 13)
  close.text:SetText("X")
  close.text:SetTextColor(0.72, 0.74, 0.79, 1)
  close:SetScript("OnClick", function() frame:Hide() end)
  attachTooltip(close, "Close", "Hide the settings window. Changes apply immediately.")

  frame:SetScript("OnHide", function()
    if CloseDropDownMenus then CloseDropDownMenus() end
  end)

  local treePanel = CreateFrame("Frame", nil, frame)
  treePanel:SetWidth(TREE_WIDTH)
  treePanel:SetHeight(VIEW_HEIGHT)
  treePanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -46)
  treePanel:SetBackdrop(PANE_BACKDROP)
  treePanel:SetBackdropColor(0.026, 0.029, 0.037, 0)
  treePanel:SetBackdropBorderColor(0, 0, 0, 0)

  local navRule = frame:CreateTexture(nil, "ARTWORK")
  navRule:SetTexture(Style.WHITE)
  navRule:SetVertexColor(0.18, 0.20, 0.25, 0.38)
  navRule:SetWidth(1)
  navRule:SetPoint("TOPLEFT", treePanel, "TOPRIGHT", 4, 0)
  navRule:SetPoint("BOTTOMLEFT", treePanel, "BOTTOMRIGHT", 4, 0)

  local viewport = CreateFrame("Frame", nil, frame)
  viewport:SetWidth(CONTENT_WIDTH)
  viewport:SetHeight(VIEW_HEIGHT)
  viewport:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + TREE_WIDTH + 9, -46)
  viewport:SetBackdrop(PANE_BACKDROP)
  viewport:SetBackdropColor(0.022, 0.025, 0.033, 0)
  viewport:SetBackdropBorderColor(0, 0, 0, 0)
  viewport:EnableMouseWheel(true)
  viewport:SetScript("OnMouseWheel", function(_, delta)
    delta = getWheelDelta(delta)
    if delta ~= 0 then Shell.ApplyScroll(owner, (owner.scrollOffset or 0) - delta * 60) end
  end)

  local scrollbar = owner.kit.createScrollbar(frame, viewport, function(offset)
    Shell.ApplyScroll(owner, offset)
  end)
  scrollbar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 4, 0)
  scrollbar:SetFrameLevel(viewport:GetFrameLevel() + 1)

  owner.frame = frame
  owner.title = title
  owner.subtitle = subtitle
  owner.headerRule = headerRule
  owner.navRule = navRule
  owner.treePanel = treePanel
  owner.viewport = viewport
  owner.scrollbar = scrollbar
  owner.treeRows = {}
  owner.pageCache = {}
  owner.currentPage = nil
  owner.uiTabs = {}
  owner.expandedWindows = true

  Shell.RebuildTree(owner)
end

function Shell.TreeNodes(owner)
  local nodes = {}
  local groups = Skada.OptionsSchema.groups
  local i, group
  for i = 1, table_getn(groups) do
    group = groups[i]
    if group.key == "windows" then
      nodes[table_getn(nodes) + 1] = { key = "windows", label = group.label, depth = 0, children = true }
      if owner.expandedWindows then
        local windows = Skada.OptionsSchema:WindowNodes()
        local i, window
        for i = 1, table_getn(windows) do
          window = windows[i]
          window.depth = 1
          nodes[table_getn(nodes) + 1] = window
        end
        nodes[table_getn(nodes) + 1] = { key = "newWindow", label = "+ New window", depth = 1, newWindow = true }
      end
    else
      nodes[table_getn(nodes) + 1] = { key = group.key, label = group.label, page = group.page, depth = 0 }
    end
  end
  return nodes
end

function Shell.AcquireNodeRow(owner, index)
  local rows = owner.treeRows
  if not rows[index] then
    local row = CreateFrame("Button", nil, owner.treePanel)
    row:RegisterForClicks("LeftButtonUp")
    row:SetWidth(TREE_WIDTH - 12)
    row:SetHeight(NODE_HEIGHT - 2)
    row:SetFrameLevel(owner.treePanel:GetFrameLevel() + 1)

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetTexture(Style.WHITE)
    local r, g, b = Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B
    row.highlight:SetVertexColor(r, g, b, 0.13)
    row.highlight:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)

    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetTexture(Style.WHITE)
    row.marker:SetVertexColor(r, g, b, 0.95)
    row.marker:SetWidth(2)
    row.marker:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
    row.marker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 3)
    row.marker:Hide()

    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetTexture(Style.WHITE)
    row.hover:SetVertexColor(1, 1, 1, 0.045)
    row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.hover:Hide()

    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetWidth(12)
    row.toggle:SetHeight(12)
    row.toggle.text = row.toggle:CreateFontString(nil, "OVERLAY")
    row.toggle.text:SetAllPoints(row.toggle)
    setUiFont(row.toggle.text, 12)

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetJustifyH("LEFT")
    setUiFont(row.label, 12)

    row:SetScript("OnEnter", function(self)
      if not self.skadaSelected then self.hover:Show() end
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)

    rows[index] = row
  end
  return rows[index]
end

function Shell.RebuildTree(owner)
  local nodes = Shell.TreeNodes(owner)
  local i, row
  for i = 1, table_getn(nodes) do
    local node = nodes[i]
    row = Shell.AcquireNodeRow(owner, i)
    row.node = node
    row:SetPoint("TOPLEFT", owner.treePanel, "TOPLEFT", 6, -6 - (i - 1) * NODE_HEIGHT)
    row:Show()

    local indent = 4 + node.depth * 14
    local hasToggle = node.children and true or false
    if hasToggle then
      row.toggle:SetPoint("LEFT", row, "LEFT", indent - 2, 0)
      row.toggle.text:SetText(owner.expandedWindows and "-" or "+")
      row.toggle:SetScript("OnClick", function()
        owner.expandedWindows = not owner.expandedWindows
        Shell.RebuildTree(owner)
      end)
      row.toggle:Show()
    else
      row.toggle:Hide()
    end

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", indent + (hasToggle and 14 or 0), 0)
    if node.depth == 0 then
      setUiFont(row.label, 10)
      row.label:SetText(string_upper(node.label))
    else
      setUiFont(row.label, 12)
      row.label:SetText(node.label)
    end
    row:SetScript("OnClick", function()
      if node.newWindow then
        local created = Skada.UI:CreateNew()
        if created then owner:SelectWindow(created) end
      elseif node.window then
        owner:SelectWindow(node.window)
      elseif node.page then
        owner:OpenPage(node.page)
      end
    end)
  end
  for i = table_getn(nodes) + 1, table_getn(owner.treeRows) do
    owner.treeRows[i].node = nil
    owner.treeRows[i]:Hide()
  end
  Shell.UpdateTreeSelection(owner)
end

function Shell.UpdateTreeSelection(owner)
  local rows = owner.treeRows
  local i, row, node
  for i = 1, table_getn(rows) do
    row = rows[i]
    node = row.node
    local selected = type(node) == "table" and node.page == owner.currentPage
      and (not node.window or node.window == owner.selectedWindow)
    if selected then
      row.highlight:Show()
      row.marker:Show()
      row.hover:Hide()
      row.skadaSelected = true
      row.label:SetTextColor(0.96, 0.97, 1, 1)
    else
      row.highlight:Hide()
      row.marker:Hide()
      row.skadaSelected = false
      if type(node) == "table" and node.depth == 0 then
        row.label:SetTextColor(0.80, 0.82, 0.87, 1)
      else
        row.label:SetTextColor(0.62, 0.65, 0.71, 1)
      end
    end
  end
end

function Shell.GetPage(owner, pageKey)
  local page = owner.pageCache[pageKey]
  if page then return page end

  local spec = Skada.OptionsSchema.pages[pageKey]
  if not spec then return nil end

  local content = CreateFrame("Frame", nil, owner.viewport)
  content:SetWidth(CONTENT_WIDTH)
  content:SetHeight(VIEW_HEIGHT)
  content.nextY = 0

  page = { content = content, rows = {}, pageKey = pageKey, tabHeights = {}, dynamic = spec.dynamicTitle }

  page.title = owner.viewport:CreateFontString(nil, "OVERLAY")
  page.title:SetPoint("TOPLEFT", owner.viewport, "TOPLEFT", 8, -9)
  setUiFont(page.title, 16)
  page.title:SetTextColor(0.95, 0.96, 0.99, 1)
  page.title:SetText(spec.dynamicTitle and "Window" or (spec.title or pageKey))
  page.title:Hide()

  page.description = owner.viewport:CreateFontString(nil, "OVERLAY")
  page.description:SetPoint("TOPLEFT", owner.viewport, "TOPLEFT", 8, -29)
  page.description:SetWidth(CONTENT_WIDTH - 20)
  page.description:SetJustifyH("LEFT")
  setUiFont(page.description, 11)
  page.description:SetTextColor(Style.MUTED_R, Style.MUTED_G, Style.MUTED_B, 1)
  page.description:SetText(PAGE_DESCRIPTIONS[pageKey] or "Skada settings.")
  page.description:Hide()

  page.rule = owner.viewport:CreateTexture(nil, "ARTWORK")
  page.rule:SetTexture(Style.WHITE)
  page.rule:SetVertexColor(0.22, 0.25, 0.31, 0.42)
  page.rule:SetHeight(1)
  page.rule:SetPoint("TOPLEFT", owner.viewport, "TOPLEFT", 8, -48)
  page.rule:SetPoint("TOPRIGHT", owner.viewport, "TOPRIGHT", -8, -48)
  page.rule:Hide()

  local groups = spec.tabs
  if groups then
    local tabSpecs = {}
    local t, tab
    for t = 1, table_getn(groups) do
      tab = groups[t]
      tabSpecs[t] = { key = tab.key, label = tab.label }
    end
    page.firstTab = tabSpecs[1].key
    page.strip = owner.kit.createTabStrip(owner.viewport, tabSpecs)
    page.strip:SetPoint("TOPLEFT", owner.viewport, "TOPLEFT", 4, -57)
    page.strip.OnChange = function(key) Shell.ActivateTab(owner, page, key) end
    page.strip:Hide()
    page.headerPad = 88
  else
    groups = { { rows = spec.rows } }
    page.headerPad = 58
  end

  local g, group, i, rowSpec, row, top
  for g = 1, table_getn(groups) do
    group = groups[g]
    if page.strip then content.nextY = 0 end
    for i = 1, table_getn(group.rows) do
      rowSpec = group.rows[i]
      top = content.nextY
      row = Shell.BuildRow(owner, content, rowSpec)
      row.rowTop = top
      row.rowBottom = content.nextY
      row.key = rowSpec.key
      row.tab = group.key
      row:EnableMouseWheel(true)
      row:SetScript("OnMouseWheel", function(_, delta)
        delta = getWheelDelta(delta)
        if delta ~= 0 then Shell.ApplyScroll(owner, (owner.scrollOffset or 0) - delta * 60) end
      end)
      page.rows[table_getn(page.rows) + 1] = row
    end
    if page.strip then page.tabHeights[group.key] = content.nextY + 8 end
  end
  page.height = content.nextY + 8

  owner.pageCache[pageKey] = page
  return page
end

function Shell.ActivateTab(owner, page, tabKey)
  if not page or not page.strip then return end
  page.activeTab = tabKey
  owner.uiTabs[page.pageKey] = tabKey
  Shell.ApplyScroll(owner, 0)
  Style:FadeIn(page.content, 0.48, 0.11, 1)
end

function Shell.SelectTab(owner, page, tabKey)
  if not page or not page.strip then return end
  page.strip:SetSelected(page.strip, tabKey)
  page.activeTab = tabKey
  owner.uiTabs[page.pageKey] = tabKey
  Shell.ApplyScroll(owner, 0)
end

function Shell.BuildRow(owner, content, rowSpec)
  local kit = owner.kit
  local widget = rowSpec.widget
  local row
  if widget == "header" then
    row = kit.createSectionHeader(content, rowSpec.label)
  elseif widget == "checkbox" then
    row = kit.createCheckbox(content, rowSpec.label, rowSpec.description, rowSpec.get, rowSpec.set)
  elseif widget == "slider" then
    row = kit.createSlider(content, rowSpec.label, rowSpec.description, rowSpec.min, rowSpec.max,
      rowSpec.step, rowSpec.format, rowSpec.get, rowSpec.set)
  elseif widget == "dropdown" then
    row = kit.createDropdown(content, rowSpec.label, rowSpec.description, rowSpec.choices, rowSpec.get, rowSpec.set)
  elseif widget == "selector" then
    row = kit.createSelector(content, rowSpec.label, rowSpec.description, rowSpec.choices, rowSpec.get, rowSpec.set)
  elseif widget == "swatch" then
    row = kit.createSwatch(content, rowSpec.label, rowSpec.description, rowSpec.get, rowSpec.set)
  elseif widget == "editbox" then
    row = kit.createEditbox(content, rowSpec.label, rowSpec.description, rowSpec.get, rowSpec.set)
  elseif widget == "action" then
    row = kit.createActionButton(content, rowSpec.label, rowSpec.description, rowSpec.onClick, rowSpec.width)
    row.refresh = function() end
  end
  return row
end

function Shell.ShowPage(owner, pageKey)
  local page = Shell.GetPage(owner, pageKey)
  if not page then return end

  local spec = Skada.OptionsSchema.pages[pageKey]
  if owner.currentPage and owner.pageCache[owner.currentPage] then
    local previous = owner.pageCache[owner.currentPage]
    previous.content:Hide()
    if previous.title then previous.title:Hide() end
    if previous.description then previous.description:Hide() end
    if previous.rule then previous.rule:Hide() end
    if previous.strip then previous.strip:Hide() end
  end
  owner.currentPage = pageKey

  if page.title then
    if page.dynamic then
      local window = owner:GetCurrentWindow()
      page.title:SetText(window and window.db.name or "Window")
    end
    page.title:Show()
  end
  if page.description then page.description:Show() end
  if page.rule then page.rule:Show() end
  if page.strip then page.strip:Show() end

  page.content:Show()
  if page.strip then
    Shell.SelectTab(owner, page, owner.uiTabs[pageKey] or page.firstTab)
  else
    owner.scrollOffset = 0
    Shell.ApplyScroll(owner, 0)
    Style:FadeIn(page.content, 0.48, 0.11, 1)
  end
  Shell.RefreshPage(owner)
end

function Shell.ApplyScroll(owner, offset)
  local page = owner.pageCache[owner.currentPage]
  if not page then return end
  local activeTab = page.activeTab
  local contentHeight = page.height
  if activeTab and page.tabHeights[activeTab] then
    contentHeight = page.tabHeights[activeTab]
  end
  local headerPad = page.headerPad or 0
  local viewHeight = VIEW_HEIGHT - headerPad
  local maxOffset = max(0, contentHeight - viewHeight)
  owner.scrollOffset = min(maxOffset, max(0, offset))

  page.content:SetPoint("TOPLEFT", owner.viewport, "TOPLEFT", 0, owner.scrollOffset - headerPad)

  local viewTop = owner.scrollOffset - headerPad
  local viewBottom = viewTop + VIEW_HEIGHT
  local i, row
  for i = 1, table_getn(page.rows) do
    row = page.rows[i]
    local inTab = not activeTab or not row.tab or row.tab == activeTab
    if inTab and row.rowTop >= viewTop and row.rowBottom <= viewBottom then
      row:Show()
    else
      row:Hide()
    end
  end

  owner.scrollbar:SetRange(contentHeight, viewHeight)
  owner.scrollbar:Update(owner.scrollOffset)
end

function Shell.RefreshPage(owner)
  local page = owner.pageCache[owner.currentPage]
  if not page then return end
  local i, row
  for i = 1, table_getn(page.rows) do
    row = page.rows[i]
    if row.refresh then row.refresh() end
  end
  if page.dynamic and page.title then
    local window = owner:GetCurrentWindow()
    page.title:SetText(window and window.db.name or "Window")
  end
end
