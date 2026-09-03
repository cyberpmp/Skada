local env = _G or getfenv(0)
local Skada = env.Skada

-- Skada's own settings dialog, built directly on this 1.12 client's frame
-- APIs -- no widget library. The options schema (options.schema.lua) stays
-- the data contract; this module turns it into chrome: a fixed-size window
-- with a sidebar tree (General + one row per meter window) and a scroll pane
-- whose controls are laid out arithmetically.
--
-- It replaces the vendored Ace3 stack, whose every rendering symptom on this
-- client (blank EditBox values, unscrolling scroll frames, strata/level
-- inversions, single-column panes) was a repair job in core.compat.lua. The
-- recipes that make this file work are the ones proven in game:
--   * sidebar rows built from scratch (the old OptionsListButtonTemplate
--     rebuild in core.compat.lua -- the client's template exists but its
--     OnLoad populates nothing);
--   * a NAMED scroll frame from UIPanelScrollFrameTemplate with an
--     explicit-size, anchorless scroll child, SetScrollChild re-called after
--     every size change and UpdateScrollChildRect after it (the client fixes
--     the scroll range at SetScrollChild time);
--   * the dialog at HIGH strata with FixLevels after every build (SetParent
--     and parent layering changes never reach children here), so StaticPopup
--     confirmations at DIALOG stay above it;
--   * pure-arithmetic layout: nothing reads a rendered rect, so there is no
--     reflow, no settle window, and a control is laid out correctly the first
--     time it is built.
local Dialog = {
  selectedGroup = "general",
}
Skada.OptionsDialog = Dialog

local SkadaCompat = env.SkadaCompat
local Common = Skada.Common
local Style = Skada.UIStyle

local table_getn = table.getn
local table_insert = table.insert
local table_sort = table.sort
local tostring = tostring
local setUiFont = Style.SetUIFont

-- Dialog sizing, derived from the inside out: three 170-unit control cells,
-- scrollbar gutter and pane chrome around them, the sidebar on the left.
local CONTROL_WIDTH = 170
local COLUMNS = 3
local CONTENT_WIDTH = COLUMNS * CONTROL_WIDTH          -- 510: control area
local CHILD_WIDTH = CONTENT_WIDTH + 8                  -- 518: scroll child
local SCROLLBAR_GUTTER = 22
local TREE_WIDTH = 175
local SIDEBAR_X = 14
local PANE_X = SIDEBAR_X + TREE_WIDTH + 14             -- 203
local PANE_WIDTH = CHILD_WIDTH + SCROLLBAR_GUTTER + 12 -- 552
local DIALOG_WIDTH = PANE_X + PANE_WIDTH + 14          -- 769
local TITLE_HEIGHT = 46
local DIALOG_HEIGHT = 560
local PANE_HEIGHT = DIALOG_HEIGHT - TITLE_HEIGHT - 14  -- 500
local ROW_GAP = 8
local WHEEL_STEP = 40

-- Control row heights, owned by the renderers.
local HEIGHTS = Skada.OptionsControls.HEIGHTS

local function controlHeight(spec)
  return HEIGHTS[spec.type] or 24
end

local root

-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------

local function createSidebarRow(sidebar)
  local row = CreateFrame("Button", nil, sidebar)
  row:SetWidth(TREE_WIDTH)
  row:SetHeight(18)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
  if highlight and highlight.SetBlendMode then highlight:SetBlendMode("ADD") end

  local marker = row:CreateTexture(nil, "ARTWORK")
  marker:SetTexture(Style.WHITE)
  marker:SetVertexColor(Style.UI_ACCENT_R, Style.UI_ACCENT_G, Style.UI_ACCENT_B, 0.92)
  marker:SetWidth(2)
  marker:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -3)
  marker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 3)
  marker:Hide()
  row.marker = marker

  row.text = row:CreateFontString(nil, "BACKGROUND")
  row.text:SetFontObject(GameFontNormalSmall)
  row.text:SetJustifyH("LEFT")
  row.text:SetHeight(18)
  row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  return row
end

local function selectGroup(groupKey)
  Dialog.selectedGroup = groupKey
  Dialog:RebuildSidebar()
  Dialog:RebuildPane()
end

local windowsHeaderRow
local windowRows = {}
local generalRow

local function paintSidebarSelection()
  if generalRow then
    if Dialog.selectedGroup == "general" then generalRow.marker:Show() else generalRow.marker:Hide() end
  end
  local rowIndex
  for rowIndex = 1, table_getn(windowRows) do
    local row = windowRows[rowIndex]
    if Dialog.selectedGroup == row.groupKey then row.marker:Show() else row.marker:Hide() end
  end
end

-- Rebuilds the sidebar rows: General, the Windows header with its
-- "+ New window" plus button, and one indented row per meter window. Rows are
-- tiny; rebuilding them on every refresh is cheaper than diffing labels that
-- rename themselves (mode switches rename windows).
function Dialog:RebuildSidebar()
  local sidebar = root.sidebar
  local rowIndex
  for rowIndex = 1, table_getn(sidebar.rows) do sidebar.rows[rowIndex]:Hide() end
  sidebar.rows = {}
  windowRows = {}
  generalRow = nil

  local y = 0

  generalRow = createSidebarRow(sidebar)
  generalRow.text:SetText("General")
  generalRow.text:SetPoint("LEFT", generalRow, "LEFT", 8, 0)
  generalRow:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -y)
  generalRow.groupKey = "general"
  generalRow:SetScript("OnClick", function() selectGroup("general") end)
  generalRow:Show()
  table_insert(sidebar.rows, generalRow)
  y = y + 18

  -- The Windows row is a header, not a button: its label must not steal
  -- clicks, and its right edge carries the plus button that creates a window.
  local headerRow = CreateFrame("Frame", nil, sidebar)
  headerRow:SetWidth(TREE_WIDTH)
  headerRow:SetHeight(18)
  headerRow:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -y)
  headerRow.text = headerRow:CreateFontString(nil, "BACKGROUND")
  headerRow.text:SetFontObject(GameFontNormalSmall)
  headerRow.text:SetJustifyH("LEFT")
  headerRow.text:SetHeight(18)
  headerRow.text:SetPoint("LEFT", headerRow, "LEFT", 8, 0)
  headerRow.text:SetText("Windows")
  local plusButton = CreateFrame("Button", nil, headerRow)
  plusButton:SetWidth(14)
  plusButton:SetHeight(14)
  plusButton:SetPoint("RIGHT", headerRow, "RIGHT", -4, 0)
  plusButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
  plusButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
  plusButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
  local plusHighlight = plusButton.GetHighlightTexture and plusButton:GetHighlightTexture()
  if plusHighlight and plusHighlight.SetBlendMode then plusHighlight:SetBlendMode("ADD") end
  plusButton:SetScript("OnClick", function()
    local created = Skada.UI:CreateNew()
    if created then Skada.Options:SelectWindow(created) end
  end)
  Common.AttachTooltip(plusButton, "New window",
    "Create another meter window and open its settings.")
  headerRow.plusButton = plusButton
  headerRow:Show()
  table_insert(sidebar.rows, headerRow)
  windowsHeaderRow = headerRow
  y = y + 18

  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex, window
  for windowIndex = 1, table_getn(windows) do
    window = windows[windowIndex]
    local row = createSidebarRow(sidebar)
    row.text:SetText(window.db.name or ("Window " .. tostring(window.db.id)))
    row.text:SetPoint("LEFT", row, "LEFT", 20, 0)
    row:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -y)
    row.groupKey = "window_" .. tostring(window.db.id)
    row:SetScript("OnClick", function() selectGroup(row.groupKey) end)
    row:Show()
    table_insert(sidebar.rows, row)
    table_insert(windowRows, row)
    y = y + 18
  end

  SkadaCompat.FixLevels(sidebar)
  paintSidebarSelection()
end

-- ---------------------------------------------------------------------------
-- Pane (scroll frame + scroll child + arithmetic layout)
-- ---------------------------------------------------------------------------

-- The pane's named scroll frame follows the 1.12 recipe proven in game: the
-- template's own "<name>ScrollBar"
-- drives clipping and the scroll range natively; the mouse wheel is wired by
-- hand (the template omits it on this client), taking the modern positional
-- delta or Vanilla's arg1.
local function createPaneScrollFrame(pane)
  local scrollframe = CreateFrame("ScrollFrame", "SkadaOptionsScrollFrame", pane, "UIPanelScrollFrameTemplate")
  scrollframe:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -6)
  scrollframe:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -6 - SCROLLBAR_GUTTER, 6)
  scrollframe:EnableMouseWheel(true)
  scrollframe:SetScript("OnMouseWheel", function(self, wheelDelta)
    local delta = Common.GetWheelDelta(wheelDelta)
    if delta == 0 then return end
    local scrollbar = root.scrollbar
    scrollbar:SetValue((scrollbar.GetValue and scrollbar:GetValue() or 0) - delta * WHEEL_STEP)
  end)

  -- The template creates its own scrollbar as "<name>ScrollBar"; adopt it, or
  -- build a stand-in when this client's template did not (the harness path).
  local scrollbar = env.SkadaOptionsScrollFrameScrollBar
  if not scrollbar then
    scrollbar = CreateFrame("Slider", "SkadaOptionsScrollFrameScrollBar", scrollframe, "UIPanelScrollBarTemplate")
    scrollbar:SetPoint("TOPLEFT", scrollframe, "TOPRIGHT", 6, -16)
    scrollbar:SetPoint("BOTTOMLEFT", scrollframe, "BOTTOMRIGHT", 6, 16)
    scrollbar:SetWidth(16)
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetValue(0)
    local scrollBackground = scrollbar:CreateTexture(nil, "BACKGROUND")
    scrollBackground:SetAllPoints(scrollbar)
    scrollBackground:SetTexture(0, 0, 0, 0.4)
  end
  root.scrollbar = scrollbar

  -- The scroll child: explicit size, NO anchor -- SetScrollChild positions
  -- it, the scroll offset moves it.
  local content = CreateFrame("Frame", nil, scrollframe)
  content:SetWidth(CHILD_WIDTH)
  content:SetHeight(1)
  scrollframe:SetScrollChild(content)
  root.content = content
  root.scrollframe = scrollframe
end

local function setScrollChildHeight(content, height)
  content:SetHeight(height)
  -- The client fixes the scroll range at SetScrollChild time; re-hand the
  -- child over (and refresh the range) after every height change.
  root.scrollframe:SetScrollChild(content)
  if root.scrollframe.UpdateScrollChildRect then
    root.scrollframe:UpdateScrollChildRect()
  end
end

-- Rebuilds the pane for the selected group: resolves the group's option
-- specs from the schema (rebuilt fresh on every call), renders each one into
-- the scroll child, and flows them into three 170-unit columns.
function Dialog:RebuildPane()
  local Controls = Skada.OptionsControls
  Controls.ClosePopup()
  Controls.ClearQueuedInputDisplays()

  local content = root.content
  -- Tear the previous pane's controls down by hiding them; the frames are
  -- released back to the engine with the child.
  local old = root.controls or {}
  local controlIndex
  for controlIndex = 1, table_getn(old) do old[controlIndex]:Hide() end
  root.controls = {}

  local options = Skada.OptionsSchema:BuildOptions()
  local specs = {}
  if self.selectedGroup == "general" then
    local specKey, spec
    for specKey, spec in pairs(options.args.general.args) do
      table_insert(specs, spec)
    end
  else
    local group = options.args.windows.args[self.selectedGroup]
    if group then
      local specKey, spec
      for specKey, spec in pairs(group.args) do
        table_insert(specs, spec)
      end
    end
  end
  table_sort(specs, function(left, right) return (left.order or 999) < (right.order or 999) end)

  -- Flow: headers and width="full" rows span the full control area; all
  -- other cells are CONTROL_WIDTH wide, three to a row. Positions come from
  -- arithmetic only -- no rendered rect is ever consulted.
  local columnIndex = 0
  local y = 0
  local rowTop = 0
  local rowHeight = 0
  local specIndex, spec
  for specIndex = 1, table_getn(specs) do
    spec = specs[specIndex]
    local isFullRow = spec.type == "header" or spec.width == "full"
    if isFullRow and columnIndex > 0 then
      y = rowTop + rowHeight + ROW_GAP
      columnIndex = 0
      rowHeight = 0
    end
    if isFullRow then
      local control = Controls.Render(content, spec, CONTENT_WIDTH)
      if control then
        control:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        control:Show()
        table_insert(root.controls, control)
      end
      y = y + (HEIGHTS[spec.type] or 24) + ROW_GAP
      rowTop = y
    else
      local height = HEIGHTS[spec.type] or 24
      local control = Controls.Render(content, spec, CONTROL_WIDTH)
      if control then
        control:SetPoint("TOPLEFT", content, "TOPLEFT", columnIndex * CONTROL_WIDTH, -y)
        control:Show()
        table_insert(root.controls, control)
      end
      if height > rowHeight then rowHeight = height end
      columnIndex = columnIndex + 1
      if columnIndex >= COLUMNS then
        y = rowTop + rowHeight + ROW_GAP
        columnIndex = 0
        rowTop = y
        rowHeight = 0
      end
    end
  end
  if columnIndex > 0 then y = rowTop + rowHeight end

  setScrollChildHeight(content, y)
end

-- ---------------------------------------------------------------------------
-- Chrome and lifecycle
-- ---------------------------------------------------------------------------

local function createRoot()
  root = CreateFrame("Frame", "SkadaOptionsFrame", UIParent)
  root:SetWidth(DIALOG_WIDTH)
  root:SetHeight(DIALOG_HEIGHT)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  -- HIGH: above the meter windows (LOW) and the normal UI (MEDIUM), below
  -- DIALOG, where the StaticPopup confirmations for delete/reset live.
  root:SetFrameStrata("HIGH")
  root:SetToplevel(false)
  root:SetMovable(true)
  root:EnableMouse(true)
  root:RegisterForDrag("LeftButton")
  root:SetScript("OnDragStart", function(self) self:StartMoving() end)
  root:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  root:SetScript("OnHide", function()
    Skada.OptionsControls.ClosePopup()
    if Skada.UI and Skada.UI.ClearSelectionVisual then Skada.UI:ClearSelectionVisual() end
  end)
  Style:ApplyFlatFrame(root, 0.96, 0.16, 0.18, 0.23)
  Style:ApplyShadow(root, true)
  Style:CreateDialogTitle(root, "Skada")
  if UISpecialFrames then
    table_insert(UISpecialFrames, "SkadaOptionsFrame") -- ESC closes
  end

  Skada.OptionsControls.SetPopupRoot(root)

  local sidebar = CreateFrame("Frame", nil, root)
  sidebar:SetWidth(TREE_WIDTH)
  sidebar:SetHeight(PANE_HEIGHT)
  sidebar:SetPoint("TOPLEFT", root, "TOPLEFT", SIDEBAR_X, -TITLE_HEIGHT)
  sidebar.rows = {}
  root.sidebar = sidebar

  local pane = CreateFrame("Frame", nil, root)
  pane:SetWidth(PANE_WIDTH)
  pane:SetHeight(PANE_HEIGHT)
  pane:SetPoint("TOPLEFT", root, "TOPLEFT", PANE_X, -TITLE_HEIGHT)
  root.pane = pane

  createPaneScrollFrame(pane)

  local close = CreateFrame("Button", nil, root)
  close:SetWidth(20)
  close:SetHeight(20)
  close:SetPoint("TOPRIGHT", root, "TOPRIGHT", -12, -10)
  Style:ApplyButton(close)
  close.label = close:CreateFontString(nil, "OVERLAY")
  close.label:SetJustifyH("CENTER")
  setUiFont(close.label, 12)
  close.label:SetText("X")
  close.label:SetAllPoints(close)
  close:SetScript("OnClick", function() Skada.Options:Close() end)

  root:Hide()
  return root
end

function Dialog:EnsureCreated()
  if not root then createRoot() end
  return root
end

function Dialog.Frame()
  return root
end

-- Validates the selected group against the current window list (a deleted
-- window's node must fall back to General before the pane build reads it).
local function resolveGroup(groupKey)
  if groupKey == "general" then return groupKey end
  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex
  for windowIndex = 1, table_getn(windows) do
    if "window_" .. tostring(windows[windowIndex].db.id) == groupKey then return groupKey end
  end
  return "general"
end

-- groupKey (optional): "general" or "window_<id>" to jump straight to a pane.
function Dialog:Open(groupKey)
  if not Skada.initialized then return end
  self:EnsureCreated()
  if groupKey then
    self.selectedGroup = resolveGroup(groupKey)
  else
    self.selectedGroup = resolveGroup(self.selectedGroup)
  end
  self:RebuildSidebar()
  self:RebuildPane()
  root:Show()
end

function Dialog:Close()
  if not root then return end
  root:Hide() -- the OnHide script closes the popup and clears the selection
end

function Dialog.IsOpen()
  return root ~= nil and root:IsShown()
end

-- Redraws the open dialog (window list changed, window renamed, mode
-- switched). No-op while closed: Open rebuilds everything anyway.
function Dialog:Refresh()
  if not root or not root:IsShown() then return end
  self.selectedGroup = resolveGroup(self.selectedGroup)
  self:RebuildSidebar()
  self:RebuildPane()
end