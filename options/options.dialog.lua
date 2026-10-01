local env = _G or getfenv(0)
local Skada = env.Skada

-- Skada's own settings dialog, built directly on this 1.12 client's frame
-- APIs -- no widget library. The options schema (options.schema.lua) stays
-- the data contract; this module turns it into chrome: a fixed-size window
-- with a sidebar (General, Appearance, Data, then one row per meter window
-- under a Windows header) and a scroll pane whose controls are laid out
-- arithmetically, one page at a time.
--
-- The chrome is the default UI's own: the dialog-box frame and header
-- ribbon, quest-log row highlights in the sidebar, a red panel Close button
-- and the round panel X -- so the window sits among the game's option
-- panels as one of them rather than as a flat dark overlay. Inside the
-- frame there is one surface: the sidebar and the page share the dialog's
-- background with a single hairline between them (inset boxes around each
-- read as frames within a frame), and the scrollbar shows only when a page
-- is taller than the pane.
--
-- The recipes that make this file work are the ones proven in game:
--   * sidebar rows built from scratch (the client's OptionsListButtonTemplate
--     exists but its OnLoad populates nothing);
--   * a NAMED scroll frame from UIPanelScrollFrameTemplate with an
--     explicit-size, anchorless scroll child, SetScrollChild re-called after
--     every size change and UpdateScrollChildRect after it (the client fixes
--     the scroll range at SetScrollChild time);
--   * the dialog at HIGH strata with FixLevels after every build (SetParent
--     and parent layering changes never reach children here), so StaticPopup
--     confirmations at DIALOG stay above it;
--   * pure-arithmetic layout: nothing reads a rendered rect, so there is no
--     reflow, no settle window, and a control is laid out correctly the first
--     time it is built;
--   * pooled frames: pane controls and sidebar rows are rebound, not
--     rebuilt, so switching pages allocates nothing once each control type
--     has been seen.
local Dialog = {
  selectedGroup = "general",
}
Skada.OptionsDialog = Dialog

local SkadaCompat = env.SkadaCompat
local Common = Skada.Common
local Style = Skada.UIStyle
local Schema = Skada.OptionsSchema

local table_getn = table.getn
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local tostring = tostring
local setGoldFont = Style.SetGoldFont
local setWhiteFont = Style.SetWhiteFont
local setGameFont = Style.SetGameFont

-- Dialog sizing, derived from the inside out: a 510-unit control area that
-- splits into two or three cells, scrollbar gutter and pane chrome around
-- it, the sidebar on the left, the header ribbon above and the Close
-- button's row below.
local CONTENT_WIDTH = 510
local CHILD_WIDTH = CONTENT_WIDTH + 8                  -- 518: scroll child
local SCROLLBAR_GUTTER = 22
local TREE_WIDTH = 175
local SIDEBAR_X = 14
local PANE_X = SIDEBAR_X + TREE_WIDTH + 14             -- 203
local PANE_WIDTH = CHILD_WIDTH + SCROLLBAR_GUTTER + 12 -- 552
local DIALOG_WIDTH = PANE_X + PANE_WIDTH + 14          -- 769
local TITLE_HEIGHT = 42
local BOTTOM_HEIGHT = 46
-- Tall enough for a window page (title, three sections, seven sliders) to
-- fit without scrolling; still under 768 for the smallest UI scale.
local DIALOG_HEIGHT = 640
local PANE_HEIGHT = DIALOG_HEIGHT - TITLE_HEIGHT - BOTTOM_HEIGHT -- 552
local ROW_GAP = 6
-- Extra air above a section heading, so sections read as blocks.
local SECTION_GAP = 10
local WHEEL_STEP = 40

-- Sidebar rows sit this far in from the sidebar's edges.
local SIDEBAR_INSET_X = 2
local SIDEBAR_INSET_Y = 8
local SIDEBAR_ROW_WIDTH = TREE_WIDTH - 2 * SIDEBAR_INSET_X
local SIDEBAR_ROW_HEIGHT = 18
-- Air between the profile pages and the Windows block.
local SIDEBAR_GROUP_GAP = 8
local SIDEBAR_WINDOW_INDENT = 20

-- The profile-wide pages, in sidebar order, before the Windows block.
local PAGES = Schema.PAGES

-- Control row heights and grid rules, owned by the renderers.
local Controls = Skada.OptionsControls
local HEIGHTS = Controls.HEIGHTS
local COLUMNS = Controls.COLUMNS
local ROW_KIND = Controls.ROW_KIND

local root

-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------

-- A sidebar row is a quest-log title: white small text for a window row,
-- gold for a page, the quest-title highlight on hover, and that same
-- highlight held lit (the `marker`) with gold text while selected. Rows are
-- pooled: a rebuild rebinds them in order and hides the surplus.
local function createSidebarRow(sidebar)
  local row = CreateFrame("Button", nil, sidebar)
  row:SetWidth(SIDEBAR_ROW_WIDTH)
  row:SetHeight(SIDEBAR_ROW_HEIGHT)
  row:SetHighlightTexture(Style.ROW_HIGHLIGHT_TEXTURE)
  local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
  if highlight and highlight.SetBlendMode then highlight:SetBlendMode("ADD") end

  local marker = row:CreateTexture(nil, "BACKGROUND")
  marker:SetTexture(Style.ROW_HIGHLIGHT_TEXTURE)
  if marker.SetBlendMode then marker:SetBlendMode("ADD") end
  marker:SetAllPoints(row)
  marker:Hide()
  row.marker = marker

  row.text = row:CreateFontString(nil, "OVERLAY")
  row.text:SetJustifyH("LEFT")
  row.text:SetHeight(SIDEBAR_ROW_HEIGHT)
  row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row:SetScript("OnClick", function()
    if row.groupKey then Dialog:Select(row.groupKey) end
  end)
  return row
end

local function acquireSidebarRow(sidebar)
  return table_remove(sidebar.rowPool) or createSidebarRow(sidebar)
end

local function releaseSidebarRow(sidebar, row)
  row:Hide()
  row:ClearAllPoints()
  row.groupKey = nil
  table_insert(sidebar.rowPool, row)
end

local function paintSidebarRow(row, selected, topLevel)
  if selected then
    row.marker:Show()
  else
    row.marker:Hide()
  end
  if selected or topLevel then
    row.text:SetTextColor(Style.GOLD_R, Style.GOLD_G, Style.GOLD_B, 1)
  else
    row.text:SetTextColor(1, 1, 1, 1)
  end
end

local function paintSidebarSelection()
  local sidebar = root.sidebar
  local rowIndex, row
  for rowIndex = 1, table_getn(sidebar.rows) do
    row = sidebar.rows[rowIndex]
    if row.groupKey then
      paintSidebarRow(row, Dialog.selectedGroup == row.groupKey, row.topLevel)
    end
  end
end

-- The Windows row is a header, not a button: its label must not steal
-- clicks, and its right edge carries the plus button that creates a window.
local function ensureWindowsHeader(sidebar)
  local headerRow = sidebar.headerRow
  if headerRow then return headerRow end
  headerRow = CreateFrame("Frame", nil, sidebar)
  headerRow:SetWidth(SIDEBAR_ROW_WIDTH)
  headerRow:SetHeight(SIDEBAR_ROW_HEIGHT)
  headerRow.text = headerRow:CreateFontString(nil, "OVERLAY")
  setGoldFont(headerRow.text, true)
  headerRow.text:SetJustifyH("LEFT")
  headerRow.text:SetHeight(SIDEBAR_ROW_HEIGHT)
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
  sidebar.headerRow = headerRow
  return headerRow
end

local function placeSidebarRow(sidebar, row, y)
  row:SetPoint("TOPLEFT", sidebar, "TOPLEFT", SIDEBAR_INSET_X, -y)
  row:Show()
  table_insert(sidebar.rows, row)
  return y + SIDEBAR_ROW_HEIGHT
end

-- Rebinds the sidebar rows: the three profile pages, the Windows header
-- with its plus button, and one indented row per meter window. Rows are
-- pooled, so a refresh (windows rename themselves on mode switches) costs
-- only relabelling.
function Dialog:RebuildSidebar()
  local sidebar = root.sidebar
  local rowIndex, row
  for rowIndex = 1, table_getn(sidebar.rows) do
    row = sidebar.rows[rowIndex]
    if row ~= sidebar.headerRow then releaseSidebarRow(sidebar, row) end
  end
  sidebar.rows = {}

  local y = SIDEBAR_INSET_Y
  local pageIndex, page
  for pageIndex = 1, table_getn(PAGES) do
    page = PAGES[pageIndex]
    row = acquireSidebarRow(sidebar)
    setGoldFont(row.text, true)
    row.text:SetText(page.name)
    row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.groupKey = page.key
    row.topLevel = true
    y = placeSidebarRow(sidebar, row, y)
  end

  y = y + SIDEBAR_GROUP_GAP
  local headerRow = ensureWindowsHeader(sidebar)
  headerRow:ClearAllPoints()
  y = placeSidebarRow(sidebar, headerRow, y)

  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex, window
  for windowIndex = 1, table_getn(windows) do
    window = windows[windowIndex]
    row = acquireSidebarRow(sidebar)
    setWhiteFont(row.text, true)
    row.text:SetText(window.db.name or ("Window " .. tostring(window.db.id)))
    row.text:SetPoint("LEFT", row, "LEFT", SIDEBAR_WINDOW_INDENT, 0)
    row.groupKey = Schema.WindowPageKey(window)
    row.topLevel = false
    y = placeSidebarRow(sidebar, row, y)
  end

  SkadaCompat.FixLevels(sidebar)
  paintSidebarSelection()
end

-- ---------------------------------------------------------------------------
-- Pane (scroll frame + scroll child + arithmetic layout)
-- ---------------------------------------------------------------------------

-- The pane's named scroll frame follows the 1.12 recipe proven in game: the
-- template's own "<name>ScrollBar" drives clipping and the scroll range
-- natively; the mouse wheel is wired by hand (the template omits it on this
-- client), taking the modern positional delta or Vanilla's arg1.
local function createPaneScrollFrame(pane)
  local scrollframe = CreateFrame("ScrollFrame", "SkadaOptionsScrollFrame", pane, "UIPanelScrollFrameTemplate")
  scrollframe:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -4)
  scrollframe:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -6 - SCROLLBAR_GUTTER, 4)
  scrollframe:EnableMouseWheel(true)
  scrollframe:SetScript("OnMouseWheel", function(self, wheelDelta)
    local delta = Common.GetWheelDelta(wheelDelta)
    if delta == 0 then return end
    local scrollbar = root.scrollbar
    if not scrollbar:IsShown() then return end
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

-- The scroll frame's own height, from the same arithmetic that sizes it.
local SCROLL_VIEW_HEIGHT = PANE_HEIGHT - 8
-- A page this tall or shorter fits without a scrollbar.
Dialog.SCROLL_VIEW_HEIGHT = SCROLL_VIEW_HEIGHT

local function setScrollChildHeight(content, height)
  content:SetHeight(height)
  -- The client fixes the scroll range at SetScrollChild time; re-hand the
  -- child over (and refresh the range) after every height change.
  root.scrollframe:SetScrollChild(content)
  if root.scrollframe.UpdateScrollChildRect then
    root.scrollframe:UpdateScrollChildRect()
  end
  -- A page that fits shows no scrollbar: the template's bar and its arrow
  -- buttons otherwise sit on every page as chrome with nothing to do.
  if height > SCROLL_VIEW_HEIGHT then
    root.scrollbar:Show()
  else
    root.scrollbar:SetValue(0)
    root.scrollbar:Hide()
  end
end

-- Places a rendered control at its cell's origin, honouring the inset a
-- renderer asks for (a panel button sits inside its row rather than on the
-- cell's edge).
local function placeControl(content, control, cellX, cellY)
  control:SetPoint("TOPLEFT", content, "TOPLEFT",
    cellX + (control.cellOffsetX or 0), -(cellY + (control.cellOffsetY or 0)))
  table_insert(root.controls, control)
end

-- The title-row action button, and how much of the title row it takes:
-- its right edge sits 6 in from the content's, so its width plus that
-- inset plus a gap.
local TITLE_ACTION_WIDTH = 120
local TITLE_ACTION_RESERVE = TITLE_ACTION_WIDTH + 6 + 8

-- The specs of one page in display order, headed by the page title. A spec
-- placed on the title row (the window page's delete button) is handed to
-- the title's action button instead of flowed into the page.
local function collectSpecs(group)
  local specs = {}
  local titleAction
  if not group then return specs, titleAction end
  local specKey, spec
  for specKey, spec in pairs(group.args) do
    if spec.placement == "title" then
      titleAction = spec
    else
      table_insert(specs, spec)
    end
  end
  table_sort(specs, function(left, right) return (left.order or 999) < (right.order or 999) end)
  table_insert(specs, 1, {
    type = "title", name = group.name, desc = group.desc,
    reserveRight = titleAction and TITLE_ACTION_RESERVE or 0,
  })
  return specs, titleAction
end

-- The title-row button dims like a page control while its spec says it
-- does not apply.
local function paintTitleAction()
  local button = root.titleAction
  local disabled = button.spec and Controls.IsDisabled(button.spec)
  button:SetAlpha(disabled and Controls.DISABLED_ALPHA or 1)
end

-- The red panel button on the page's title row, top-right of the pane,
-- bound to the page's title-row spec (Delete window) or hidden when the
-- page has none: the action sits with the page it acts on.
local function bindTitleAction(spec)
  local button = root.titleAction
  button.spec = spec
  if not spec then
    button:Hide()
    return
  end
  button:SetText(spec.name)
  if spec.desc then
    Common.AttachTooltip(button, spec.name, spec.desc)
  else
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
  end
  -- A root child starts below the scroll frame and its content; lift it
  -- over the page's controls so nothing on the title row draws across it.
  button:SetFrameLevel((root.content:GetFrameLevel() or 0) + 10)
  paintTitleAction()
  button:Show()
end

-- Rebuilds the pane for the selected page: resolves the page's option
-- specs from the schema (built fresh on every call), binds a pooled control
-- to each one, and flows them into rows. Positions come from arithmetic
-- only -- no rendered rect is ever consulted.
--
-- Flow: a control takes CONTENT_WIDTH / columns for its type (see
-- Controls.COLUMNS); types without a column count, and any spec with
-- width="full", span the row. A row only ever holds controls of one row
-- kind (Controls.ROW_KIND), so check boxes line up with check boxes and
-- sliders with sliders; a spec may also ask for a fresh row (newRow).
function Dialog:RebuildPane()
  -- Rebuilding the page already on screen (a window renamed itself, say)
  -- leaves the player's interaction alone: an open dropdown stays open and
  -- a name being typed keeps its text and focus.
  local samePage = self.builtGroup == self.selectedGroup
  if not samePage then Controls.ClosePopup() end
  Controls.ClearQueuedInputDisplays()

  local content = root.content
  local old = root.controls or {}
  local controlIndex
  -- Released last-first: each pool hands frames back last-in-first-out, so
  -- the same page rebuilt binds every option to the frame it had (a slider
  -- held mid-drag keeps writing its own setting, not a neighbour's).
  for controlIndex = table_getn(old), 1, -1 do Controls.Release(old[controlIndex], samePage) end
  root.controls = {}

  local specs, titleAction = collectSpecs(Schema:BuildGroup(self.selectedGroup))
  bindTitleAction(titleAction)

  local y, rowTop, rowHeight, columnIndex, rowKind = 0, 0, 0, 0, nil
  local function closeRow()
    if columnIndex > 0 then y = rowTop + rowHeight + ROW_GAP end
    columnIndex, rowHeight, rowKind = 0, 0, nil
    rowTop = y
  end

  local specIndex, spec
  for specIndex = 1, table_getn(specs) do
    spec = specs[specIndex]
    local kind = ROW_KIND[spec.type]
    local columns = 1
    if kind and spec.width ~= "full" then columns = COLUMNS[spec.type] or 1 end
    local isFullRow = columns == 1
    if isFullRow or kind ~= rowKind or columnIndex >= columns or spec.newRow then closeRow() end
    if spec.type == "header" and y > 0 then
      y = y + SECTION_GAP
      rowTop = y
    end
    local cellWidth = CONTENT_WIDTH / columns
    local control = Controls.Render(content, spec, cellWidth)
    if control then placeControl(content, control, columnIndex * cellWidth, y) end
    local height = HEIGHTS[spec.type] or 24
    if isFullRow then
      y = y + height + ROW_GAP
      rowTop = y
    else
      if height > rowHeight then rowHeight = height end
      columnIndex = columnIndex + 1
      rowKind = kind
    end
  end
  closeRow()

  setScrollChildHeight(content, y)
  if not samePage then
    root.scrollbar:SetValue(0)
    self.builtGroup = self.selectedGroup
  end
end

-- Repaints every control on the page except the one that just committed,
-- so dependents (a swatch behind its toggle, size matching behind the
-- snap toggle, the segment behind a live mode) follow the change at once.
-- `force` re-resolves cached labels (outside changes can relabel).
function Dialog:RefreshControls(source, force)
  if not root then return end
  local controls = root.controls or {}
  local controlIndex, control
  for controlIndex = 1, table_getn(controls) do
    control = controls[controlIndex]
    if control ~= source then Controls.Refresh(control, force) end
  end
  paintTitleAction()
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
    Controls.ClosePopup()
    -- A hidden name box must not keep the keyboard.
    local controls = root.controls or {}
    local controlIndex
    for controlIndex = 1, table_getn(controls) do
      if controls[controlIndex].blur then controls[controlIndex].blur() end
    end
    if Skada.UI and Skada.UI.ClearSelectionVisual then Skada.UI:ClearSelectionVisual() end
  end)
  Style:ApplyDialogFrame(root)
  root.dialogTitle = Style:CreateDialogTitle(root, "Skada")
  if UISpecialFrames then
    table_insert(UISpecialFrames, "SkadaOptionsFrame") -- ESC closes
  end

  Controls.SetPopupRoot(root)
  Controls.SetCommitListener(function(source) Dialog:RefreshControls(source) end)

  local sidebar = CreateFrame("Frame", nil, root)
  sidebar:SetWidth(TREE_WIDTH)
  sidebar:SetHeight(PANE_HEIGHT)
  sidebar:SetPoint("TOPLEFT", root, "TOPLEFT", SIDEBAR_X, -TITLE_HEIGHT)
  sidebar.rows = {}
  sidebar.rowPool = {}
  root.sidebar = sidebar

  local pane = CreateFrame("Frame", nil, root)
  pane:SetWidth(PANE_WIDTH)
  pane:SetHeight(PANE_HEIGHT)
  pane:SetPoint("TOPLEFT", root, "TOPLEFT", PANE_X, -TITLE_HEIGHT)
  root.pane = pane

  -- The one line inside the frame: a hairline between sidebar and page,
  -- in the muted grey the section rules use.
  local divider = root:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(Style.WHITE)
  divider:SetWidth(1)
  divider:SetPoint("TOP", sidebar, "TOPRIGHT", 7, -4)
  divider:SetPoint("BOTTOM", sidebar, "BOTTOMRIGHT", 7, 4)
  divider:SetVertexColor(Style.RULE_R, Style.RULE_G, Style.RULE_B, Style.RULE_A)
  root.divider = divider

  createPaneScrollFrame(pane)

  local function close() Skada.Options:Close() end

  root.closeButton = Style:CreatePanelButton(root, CLOSE or "Close", 100, 22)
  root.closeButton:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -27, 17)
  root.closeButton:SetScript("OnClick", close)

  root.closeX = Style:CreateCloseButton(root, close)

  -- The page's action (Delete window) sits on the title row at the
  -- pane's top-right, level with the page name, so it belongs visibly to
  -- the window it deletes and never needs scrolling to reach. A root child
  -- rather than a pooled control, lifted above the scroll frame's level
  -- each time it is bound (bindTitleAction).
  root.titleAction = Style:CreatePanelButton(root, "", TITLE_ACTION_WIDTH, 22)
  root.titleAction:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -(SCROLLBAR_GUTTER + 12), -12)
  root.titleAction:SetScript("OnClick", function()
    local spec = root.titleAction.spec
    if spec and spec.func and not Controls.IsDisabled(spec) then spec.func() end
  end)
  root.titleAction:Hide()

  -- The version, muted, beside the Close button: what a tester reads off a
  -- screenshot without opening chat.
  local versionText = root:CreateFontString(nil, "OVERLAY")
  versionText:SetJustifyH("RIGHT")
  setGameFont(versionText, "GameFontDisableSmall", 10, 0.5, 0.5, 0.5)
  versionText:SetHeight(14)
  versionText:SetPoint("RIGHT", root.closeButton, "LEFT", -12, 0)
  versionText:SetText("Skada " .. tostring(Skada.version or ""))
  root.versionText = versionText

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

-- Validates a page key against the pages that exist right now (a deleted
-- window's page must fall back to General before the pane build reads it).
local function resolveGroup(groupKey)
  if Schema.IsProfilePage(groupKey) or Schema.WindowForPage(groupKey) then return groupKey end
  return "general"
end

-- Shows a page in the open dialog (a sidebar click).
function Dialog:Select(groupKey)
  self.selectedGroup = resolveGroup(groupKey)
  paintSidebarSelection()
  self:RebuildPane()
end

-- groupKey (optional): "general", "appearance", "data" or "window_<id>" to
-- jump straight to a page.
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

-- Batching: while open, Refresh and RepaintControls only note that they
-- are owed; the last EndBatch pays the debt once (a rebuild covers a
-- repaint).
local batchDepth = 0
local owesRebuild, owesRepaint = false, false

function Dialog:BeginBatch()
  batchDepth = batchDepth + 1
end

function Dialog:EndBatch()
  if batchDepth > 0 then batchDepth = batchDepth - 1 end
  if batchDepth > 0 then return end
  local rebuild, repaint = owesRebuild, owesRepaint
  owesRebuild, owesRepaint = false, false
  if rebuild then
    self:Refresh()
  elseif repaint then
    self:RepaintControls()
  end
end

-- Repaints the open page from current values after a change made outside
-- the dialog. A change the dialog itself is committing is skipped: the
-- committing control repaints its page when it is done (notifyCommitted),
-- and a slider drag would otherwise repaint the page on every tick.
function Dialog:RepaintControls()
  if not root or not root:IsShown() then return end
  if Controls.IsCommitting() then return end
  if batchDepth > 0 then
    owesRepaint = true
    return
  end
  self:RefreshControls(nil, true)
end

-- Redraws the open dialog (window list changed, window renamed, mode
-- switched). No-op while closed: Open rebuilds everything anyway.
function Dialog:Refresh()
  if not root or not root:IsShown() then return end
  if batchDepth > 0 then
    owesRebuild = true
    return
  end
  self.selectedGroup = resolveGroup(self.selectedGroup)
  self:RebuildSidebar()
  self:RebuildPane()
end
