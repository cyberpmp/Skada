local Skada = (_G or getfenv(0)).Skada

local UI = { windows = {}, byID = {} }
Skada.UI = UI

local windowMeta = { __index = UI }

local Common = Skada.Common
local getClickButton = Common.GetClickButton
local getWheelDelta = Common.GetWheelDelta
local Style = Skada.UIStyle

local max = math.max
local min = math.min
local table_getn = table.getn

local backdrop = Common.BACKDROP

local setReadableFont = Common.SetFont

local WindowConfig = Skada.WindowConfig
local applyWindowDefaults = WindowConfig.ApplyDefaults

local SnapDock = Skada.UISnapDock
local persistGeometry = SnapDock.PersistGeometry

local UIReport = Skada.UIReport

local Presenter = Skada.UIPresenter
UI.GetEntry = Presenter.GetEntry
UI.ClearDisplay = Presenter.ClearDisplay
UI.BuildThreatDisplay = Presenter.BuildThreatDisplay
UI.BuildModeDisplay = Presenter.BuildModeDisplay
UI.BuildModesDisplay = Presenter.BuildModesDisplay
UI.BuildSegmentsDisplay = Presenter.BuildSegmentsDisplay
UI.BuildDisplay = Presenter.BuildDisplay
UI.FormatDuration = Presenter.FormatDuration
UI.GetEntryText = Presenter.GetEntryText
UI.GetTitle = Presenter.GetTitle
UI.ShowEntryTooltip = Presenter.ShowEntryTooltip

local Renderer = Skada.UIRowRenderer
UI.CreateRow = Renderer.CreateRow
UI.EnsureRows = Renderer.EnsureRows
UI.ApplyLayout = Renderer.ApplyLayout

-- Every drag surface (title bar, window background, hidden-header menu slot,
-- meter bar) shares one move/snap/persist sequence; flagName names the
-- per-surface "this was a drag, swallow the click" marker its OnClick reads.
function UI:BeginWindowDrag(flagName)
  if self.db.locked then return end
  self.manager:SetActive(self)
  if self.actionMenu then self.actionMenu:Hide() end
  self[flagName] = true
  self.frame:StartMoving()
end

function UI:EndWindowDrag()
  self.frame:StopMovingOrSizing()
  self.manager:SnapWindow(self)
  persistGeometry(self, true)
  Skada:MarkDirty()
end
UI.GetPinnedPlayerEntry = Renderer.GetPinnedPlayerEntry
UI.PaintRows = Renderer.PaintRows
UI.AnimateAll = Renderer.AnimateAll
UI.Animate = Renderer.Animate

UI.SnapWindow = SnapDock.SnapWindow

local Report = Skada.UIReport
UI.ShowResetPopup = Report.ShowResetPopup
UI.BuildReportLines = Report.BuildReportLines
UI.Report = Report.Report
UI.ShowReportPopup = Report.ShowReportPopup

function UI:NeedsContinuousRefresh()
  local windows = self.windows
  local i, window
  for i = 1, table_getn(windows) do
    window = windows[i]
    if window.db.visible then
      if window.db.mode == "threat" then

        if Skada.Threat and Skada.Threat.NeedsUpdates and Skada.Threat:NeedsUpdates() then
          return true
        end
      elseif Skada.Data and Skada.Data.active then
        return true
      end
    end
  end
  return false
end

function UI:SetView(view)
  self.view = view or "mode"
  self.detailActor = nil
  self.scrollOffset = 0
  Skada:MarkDirty()
end

function UI:Back()
  if self.detailActor then
    self.detailActor = nil
    self.scrollOffset = 0
  elseif self.view == "mode" then
    self.view = "modes"
    self.scrollOffset = 0
  elseif self.view == "modes" then
    self.view = "segments"
    self.scrollOffset = 0
  else
    return
  end
  Skada:MarkDirty()
end

function UI:Forward()
  if self.view == "segments" then
    self.view = "modes"
  elseif self.view == "modes" then
    self.view = "mode"
  else
    return
  end
  self.detailActor = nil
  self.scrollOffset = 0
  Skada:MarkDirty()
end

function UI:SelectEntry(entry)
  if not entry then return end
  if entry.modeKey then
    -- through Modes:Set so auto-named windows follow the mode's title
    Skada.Modes:Set(entry.modeKey, self)
    self.manager:SyncLegacy(self)
    self:SetView("mode")
  elseif entry.segment ~= nil then
    self.db.segment = entry.segment
    self.manager:SyncLegacy(self)

    self:SetView("modes")
  elseif entry.actor and not entry.spell then
    local mode = Skada.Modes:Get(self.db.mode)
    if mode.detail then
      self.detailActor = entry.actor.name
      self.scrollOffset = 0
      Skada:MarkDirty()
    end
  end
end

function UI:Scroll(direction)
  if not direction or direction == 0 then return end
  if self.view == "mode" and self.db.mode == "threat" then
    self.scrollOffset = 0
    return
  end
  local page = self.db.rows
  local maximum = max(0, (self.displayCount or 0) - page)
  local offset = self.scrollOffset or 0
  if direction > 0 then offset = offset - 1 else offset = offset + 1 end
  local clamped = min(maximum, max(0, offset))
  if clamped == self.scrollOffset then return end
  self.scrollOffset = clamped
  self:PaintRows()
end

function UI:Refresh()
  if not self.frame then return end
  if self.layoutDirty then
    self:ApplyLayout()
    self.layoutDirty = false
  end
  if not self.db.visible then return end

  local set = Skada.Data:GetSelectedSet(self.db.segment)
  local mode = Skada.Modes:Get(self.db.mode)
  local count = self:BuildDisplay(set, mode)
  self.displayCount = count

  self.paintSet = set
  self.paintMode = mode
  self.paintLive = mode.live
  local maximum = count > 0 and self.display[1].value or 1
  if mode.live and Skada.Threat and Skada.Threat.rows and Skada.Threat.rows[1] then
    maximum = Skada.Threat.rows[1].threat or maximum
  end
  if self.view ~= "mode" then maximum = 1 end
  self.paintMaximum = maximum
  self.currentTitle = self:GetTitle(mode)
  self.title:SetText(self.currentTitle)
  if self.actionMenu and self.actionMenu:IsShown() then self.actionMenu:Refresh() end

  self:PaintRows()
end

function UI:InitializeWindow(config)
  local owner = self
  self.db = config

  local frame = CreateFrame("Frame", "SkadaBarWindow" .. tostring(config.id), UIParent)
  self.frame = frame
  frame:SetFrameStrata("LOW")
  frame:SetBackdrop(backdrop)
  Style:ApplyMeterWindow(frame, false, Style:GetWindowOpacity(config))
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    delta = getWheelDelta(delta)
    if delta ~= 0 then
      owner.manager:SetActive(owner)
      owner:Scroll(delta)
    end
  end)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    owner:BeginWindowDrag("headerWasDragged")
  end)
  frame:SetScript("OnDragStop", function()
    owner:EndWindowDrag()
  end)

  local header = CreateFrame("Button", nil, frame)
  self.header = header
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", Style.WINDOW_PADDING, -Style.WINDOW_PADDING)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Style.WINDOW_PADDING, -Style.WINDOW_PADDING)
  header:SetHeight(Style.HEADER_BUTTON_HEIGHT)
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  header:RegisterForDrag("LeftButton")

  local headerTexture = header:CreateTexture(nil, "BACKGROUND")
  self.headerTexture = headerTexture
  headerTexture:SetAllPoints(header)

  local headerRule = header:CreateTexture(nil, "ARTWORK")
  self.headerRule = headerRule
  headerRule:SetTexture(Style.WHITE)
  headerRule:SetHeight(1)
  headerRule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  headerRule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
  Style:ApplyHeader(self)

  local menuButton = UIReport:CreateHeaderButton(header, {
    texture = "Interface\\Icons\\INV_Misc_Gear_01", title = "More actions",
    description = "Settings, logging, reporting, window actions, and reset.",
    click = function()
      owner.manager:SetActive(owner)
      owner.actionMenu:Toggle()
    end,
  })
  self.menuButton = menuButton
  menuButton:SetPoint("RIGHT", header, "RIGHT", -2, 0)

  local autoButton = UIReport:CreateHeaderButton(header, {
    text = "A", textSize = 12, textOffsetX = 2, activeMarker = false,
    title = "Automatic segments",
    description = "Toggle Current in combat and Overall out of combat for this window.",
    click = function()
      owner.manager:SetActive(owner)
      owner.db.autoSwitch = not owner.db.autoSwitch
      if owner.db.autoSwitch then owner:ApplyCombatState(Skada.Data.clientInCombat) end
      Style:SetButtonActive(owner.autoButton, owner.db.autoSwitch, 0.20, 1, 0.20)
      owner.manager:SyncLegacy(owner)
      Skada:MarkDirty()
    end,
  })
  self.autoButton = autoButton
  autoButton:SetPoint("RIGHT", menuButton, "LEFT", -Style.HEADER_BUTTON_GAP, 0)

  local modeButton = UIReport:CreateHeaderButton(header, {
    texture = "Interface\\Icons\\Spell_Nature_Lightning", title = "Mode",
    description = "Show the Skada mode list.",
    click = function() owner.manager:SetActive(owner) owner:SetView("modes") end,
  })
  self.modeButton = modeButton
  modeButton:SetPoint("RIGHT", autoButton, "LEFT", -Style.HEADER_BUTTON_GAP, 0)

  self.actionMenu = UIReport:CreateActionMenu(owner, menuButton)

  local title = header:CreateFontString(nil, "OVERLAY")
  self.title = title
  title:SetPoint("LEFT", header, "LEFT", 5, 0)
  title:SetPoint("RIGHT", modeButton, "LEFT", -3, 0)
  title:SetJustifyH("LEFT")
  setReadableFont(title, 13)
  title:SetText(config.name or "Skada")
  Style:ApplyHeader(self)

  header:SetScript("OnDragStart", function()
    owner:BeginWindowDrag("headerWasDragged")
  end)
  header:SetScript("OnDragStop", function()
    owner:EndWindowDrag()
  end)
  header:SetScript("OnClick", function(self, button)
    button = getClickButton(button)
    owner.manager:SetActive(owner)
    owner.actionMenu:Hide()
    if owner.headerWasDragged then
      owner.headerWasDragged = false
      return
    end
    if button == "RightButton" then owner:Back() else owner:Forward() end
  end)
  header:SetScript("OnMouseDown", function() owner.headerWasDragged = false end)

  local headerButtons = { menuButton, autoButton, modeButton }
  self.headerButtons = headerButtons
  local i
  for i = 1, table_getn(headerButtons) do headerButtons[i]:SetAlpha(Style.HEADER_BUTTON_ALPHA) end
  header:SetScript("OnEnter", function(self)
    local i
    for i = 1, table_getn(headerButtons) do headerButtons[i]:SetAlpha(1) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(owner.currentTitle or config.name or "Skada", 1, 0.5, 0)
    GameTooltip:AddLine("Left-click forward, right-click back, or drag to move.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("This window has independent mode and segment settings.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  header:SetScript("OnLeave", function()
    local i
    for i = 1, table_getn(headerButtons) do headerButtons[i]:SetAlpha(Style.HEADER_BUTTON_ALPHA) end
    GameTooltip:Hide()
  end)

  -- When the title bar is hidden, this button occupies the top-bar slot so the
  -- header's navigation and dragging keep working with no header visible.
  local clickCatcher = CreateFrame("Button", nil, frame)
  self.clickCatcher = clickCatcher
  clickCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  clickCatcher:RegisterForDrag("LeftButton")
  clickCatcher:SetScript("OnDragStart", function()
    owner:BeginWindowDrag("headerWasDragged")
  end)
  clickCatcher:SetScript("OnDragStop", function()
    owner:EndWindowDrag()
  end)
  clickCatcher:SetScript("OnClick", function(self, button)
    button = getClickButton(button)
    owner.manager:SetActive(owner)
    if owner.headerWasDragged then
      owner.headerWasDragged = false
      return
    end
    if button == "RightButton" then
      -- With the title bar hidden this slot is the window's menu bar.
      owner.actionMenu:Toggle()
    else
      owner.actionMenu:Hide()
      owner:Forward()
    end
  end)
  clickCatcher:SetScript("OnMouseDown", function() owner.headerWasDragged = false end)
  clickCatcher:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(owner.currentTitle or config.name or "Skada", 1, 0.5, 0)
    GameTooltip:AddLine("Title bar hidden: right-click for the menu, left-click forward, drag to move.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  clickCatcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Created before the rows and at their default level it would lose
  -- hit-testing to row 1; sit above the rows or the hidden-header menu
  -- bar slot never receives clicks.
  clickCatcher:SetFrameLevel(frame:GetFrameLevel() + 2)
  clickCatcher:Hide()

  local resizeButton = CreateFrame("Button", nil, frame)
  self.resizeButton = resizeButton
  resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  resizeButton:SetWidth(14)
  resizeButton:SetHeight(14)
  resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resizeButton:SetAlpha(0.40)
  resizeButton:SetScript("OnEnter", function() resizeButton:SetAlpha(0.92) end)
  resizeButton:SetScript("OnLeave", function() resizeButton:SetAlpha(0.40) end)
  resizeButton:SetScript("OnMouseDown", function(self, button)
    button = getClickButton(button)
    owner.manager:SetActive(owner)
    if button == "LeftButton" and not config.locked then frame:StartSizing("BOTTOMRIGHT") end
  end)
  resizeButton:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    persistGeometry(owner, false)
    Skada:MarkDirty()
  end)

  self.layoutDirty = true
  self:ApplyLayout()
  self.layoutDirty = false
  self:Refresh()
end

function UI:SyncLegacy(window)
  return WindowConfig.SyncLegacy(self, window)
end

function UI:GetPrimary()
  return self.windows[1]
end

function UI:GetActive()
  return self.activeWindow or self:GetPrimary()
end

function UI:GetWindow(value)
  if not value or value == "" then return self:GetActive() end
  local numeric = tonumber(value)
  if numeric and self.byID[numeric] then return self.byID[numeric] end
  local lowered = string.lower(tostring(value))
  local i, window
  for i = 1, table_getn(self.windows) do
    window = self.windows[i]
    if string.lower(window.db.name or "") == lowered then return window end
  end
end

function UI:SetActive(window)
  if not window then return end
  self.activeWindow = window
  self.visualActive = window
  Skada.db.profile.selectedWindowID = window.db.id
  local i, candidate
  for i = 1, table_getn(self.windows) do
    candidate = self.windows[i]
    if candidate ~= window and candidate.actionMenu then candidate.actionMenu:Hide() end
    Style:ApplyMeterWindow(candidate.frame, candidate == window, Style:GetWindowOpacity(candidate.db))
    Style:ApplyHeader(candidate)
  end
end

-- Drops the "selected" border highlight when the settings window closes so
-- no meter is left looking picked. The logical target follows the visual:
-- with nothing highlighted, GetActive falls back to the primary window
-- instead of silently acting on the last-edited meter.
function UI:ClearSelectionVisual()
  self.visualActive = nil
  self.activeWindow = nil
  local i, candidate
  for i = 1, table_getn(self.windows) do
    candidate = self.windows[i]
    Style:ApplyMeterWindow(candidate.frame, false, Style:GetWindowOpacity(candidate.db))
    Style:ApplyHeader(candidate)
  end
end

function UI:CreateWindow(config)
  local window = setmetatable({
    manager = self,
    rows = {},
    entryPool = {},
    display = {},
    segmentChoices = {},
    view = "mode",
    scrollOffset = 0,
    displayCount = 0,
  }, windowMeta)
  applyWindowDefaults(config, Skada.db.profile)
  window:InitializeWindow(config)
  self.windows[table_getn(self.windows) + 1] = window
  self.byID[config.id] = window
  return window
end

function UI:CreateNew(name)
  local source = self:GetActive() or self:GetPrimary()
  local profile = Skada.db.profile
  local id = profile.nextWindowID or 2
  profile.nextWindowID = id + 1
  local config = { id = id }
  applyWindowDefaults(config, source and source.db or profile)
  config.name = name and name ~= "" and name or Skada.Modes:Get(config.mode).title
  -- a name supplied here is the user's own; an inherited name never is, or
  -- the new window would never follow its mode's title
  config.nameIsCustom = name ~= nil and name ~= ""
  config.visible = true
  config.x = (source and source.db.x or 0) + 28
  config.y = (source and source.db.y or 0) - 28
  config.segment = Skada.Data.clientInCombat and "current" or "total"
  if Skada.Modes:Get(config.mode).live then config.segment = "current" end
  profile.windows[table_getn(profile.windows) + 1] = config
  local window = self:CreateWindow(config)
  self:SetActive(window)
  Skada:MarkDirty()
  Skada:Print("Created window " .. config.id .. " (" .. config.name .. ").")
  Skada:Publish("windowListChanged", self)
  return window
end

function UI:DeleteWindow(window)
  if not window or table_getn(self.windows) <= 1 then
    Skada:Print("At least one Skada window must remain.")
    return false
  end
  local i
  if window.actionMenu then window.actionMenu:Hide() end
  window.frame:Hide()
  self.byID[window.db.id] = nil
  for i = table_getn(self.windows), 1, -1 do
    if self.windows[i] == window then table.remove(self.windows, i) break end
  end
  for i = table_getn(Skada.db.profile.windows), 1, -1 do
    if Skada.db.profile.windows[i] == window.db then
      table.remove(Skada.db.profile.windows, i)
      break
    end
  end
  self.activeWindow = self:GetPrimary()
  self:SetActive(self.activeWindow)
  self:SyncLegacy(self:GetPrimary())
  Skada:MarkDirty()
  Skada:Print("Removed window " .. tostring(window.db.id) .. ".")
  Skada:Publish("windowListChanged", self)
  return true
end

function UI:RequestDelete(window)
  if table_getn(self.windows) <= 1 then
    Skada:Print("At least one Skada window must remain.")
  elseif StaticPopup_Show then
    self.pendingDelete = window
    StaticPopup_Show("SKADA_DELETE_WINDOW")
  else
    self:DeleteWindow(window)
  end
end

function UI:RefreshAll()
  local i, window
  for i = 1, table_getn(self.windows) do
    window = self.windows[i]
    window:Refresh()
    Style:SetButtonActive(window.autoButton, window.db.autoSwitch, 0.20, 1, 0.20)
    if not window.db.visible and window.actionMenu then window.actionMenu:Hide() end
  end

  self.animateUntil = GetTime() + 0.6
end

function UI:ApplyCombatState(inCombat)
  local combatMode = self.db.combatMode
  local renamed = false
  if inCombat and combatMode and combatMode ~= "" and combatMode ~= self.db.mode then
    -- keep the pre-combat mode; a later call must not overwrite it with the
    -- already-switched mode
    if self.db.returnAfterCombat and not self.restoreMode then
      self.restoreMode = self.db.mode
    end
    local _, modeRenamed = Skada.Modes:Set(combatMode, self)
    renamed = modeRenamed
  elseif not inCombat and self.restoreMode then
    local _, modeRenamed = Skada.Modes:Set(self.restoreMode, self)
    renamed = modeRenamed
    self.restoreMode = nil
  end
  -- unchecking "return after combat" mid-fight must drop the pending restore
  if inCombat and not self.db.returnAfterCombat then self.restoreMode = nil end
  if Skada.Modes:Get(self.db.mode).live then self.db.segment = "current" end
  if not self.db.autoSwitch then return renamed end
  if not Skada.Modes:Get(self.db.mode).live then
    self.db.segment = inCombat and "current" or "total"
  end
  self.detailActor = nil
  self.view = "mode"
  self.scrollOffset = 0
  self.manager:SyncLegacy(self)
  return renamed
end

function UI:OnCombatState(inCombat)
  local i, renamed
  renamed = false
  for i = 1, table_getn(self.windows) do
    if self.windows[i]:ApplyCombatState(inCombat) then renamed = true end
  end
  Skada:MarkDirty()
  if renamed and Skada.Options and Skada.Options.frame and Skada.OptionsShell then
    Skada.OptionsShell.RebuildTree(Skada.Options)
  end
end

function UI:ResetViews(resetSegments)
  local i, window
  for i = 1, table_getn(self.windows) do
    window = self.windows[i]
    window.detailActor = nil
    window.view = "mode"
    window.scrollOffset = 0
    if resetSegments then
      if Skada.Modes:Get(window.db.mode).live then
        window.db.segment = "current"
      else
        window.db.segment = window.db.autoSwitch and (Skada.Data.clientInCombat and "current" or "total") or "current"
      end
    end
  end
  self:SyncLegacy(self:GetPrimary())
end

function UI:MarkLayouts()
  local i
  for i = 1, table_getn(self.windows) do self.windows[i].layoutDirty = true end
end

function UI:Initialize()
  local profile = Skada.db.profile

  if StaticPopupDialogs then
    StaticPopupDialogs.SKADA_RESET_DATA = {
      text = "Reset all Skada fight data?", button1 = YES or "Yes", button2 = NO or "No",
      OnAccept = function() Skada.Data:Reset() end, timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    StaticPopupDialogs.SKADA_DELETE_WINDOW = {
      text = "Remove this Skada window?", button1 = YES or "Yes", button2 = NO or "No",
      OnAccept = function() if UI.pendingDelete then UI:DeleteWindow(UI.pendingDelete) UI.pendingDelete = nil end end,
      OnCancel = function() UI.pendingDelete = nil end,
      timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
    StaticPopupDialogs.SKADA_RESET_POLICY = {
      text = "Reset Skada data for the new encounter context?", button1 = YES or "Yes", button2 = NO or "No",
      OnAccept = function() Skada.Data:Reset() end, timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
  end

  profile.windows = profile.windows or {}

  WindowConfig.Migrate(profile)

  if table_getn(profile.windows) == 0 then
    local first = { id = 1 }
    applyWindowDefaults(first, profile)
    first.name = Skada.Modes:Get(first.mode).title
    profile.windows[1] = first
  end

  local i, config, highest, window
  highest = 0
  for i = 1, table_getn(profile.windows) do
    config = profile.windows[i]
    config.id = config.id or i
    config.name = config.name or (config.id == 1 and "Skada" or ("Skada " .. config.id))
    applyWindowDefaults(config, profile)
    window = self:CreateWindow(config)
    if config.id > highest then highest = config.id end
    if config.id == profile.selectedWindowID then self.activeWindow = window end
  end
  profile.nextWindowID = max(profile.nextWindowID or 1, highest + 1)
  self:SetActive(self.activeWindow or self:GetPrimary())
  self:OnCombatState(Skada.Data.clientInCombat)
  self:RefreshAll()
end

if Skada.Threat and Skada.Threat.SetWindowEnumerator then
  Skada.Threat:SetWindowEnumerator(function() return UI.windows end)
end

Skada:Subscribe("combatStateChanged", function(inCombat)
  UI:OnCombatState(inCombat)
end)

Skada:Subscribe("dataReset", function()
  UI:ResetViews(true)
end)

Skada:RegisterInitializer(function() UI:Initialize() end, "bar windows")

local RenderPolicy = {}

function RenderPolicy:ShouldRebuild()
  return Skada.dirty or (UI.NeedsContinuousRefresh and Skada.UI:NeedsContinuousRefresh())
end

function RenderPolicy:Rebuild()
  Skada.UI:RefreshAll()
end

function RenderPolicy:ShouldAnimate(now)
  return Skada.UI:NeedsContinuousRefresh()
    or (Skada.UI.animateUntil and now < Skada.UI.animateUntil)
end

function RenderPolicy:Animate()
  Skada.UI:AnimateAll()
end

Skada:RegisterRenderPolicy(RenderPolicy)
