local Skada = (_G or getfenv(0)).Skada

local UI = { windows = {}, byID = {} }
Skada.UI = UI

local windowMeta = { __index = UI }

local Common = Skada.Common
local getClickButton = Common.GetClickButton
local getWheelDelta = Common.GetWheelDelta
local getTooltip = Common.GetTooltip
local Style = Skada.UIStyle

local floor = math.floor
local max = math.max
local min = math.min
local table_getn = table.getn

local setReadableFont = Common.SetFont

local WindowConfig = Skada.WindowConfig
local applyWindowDefaults = WindowConfig.ApplyDefaults
local getVisibleRowCount = WindowConfig.GetVisibleRowCount

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

function UI:NeedsContinuousRefresh(now)
  local windows = self.windows
  local data = Skada.Data
  local dataActive = data and data.active
  local wantsThreat = false
  local windowIndex, window, set, mode
  for windowIndex = 1, table_getn(windows) do
    window = windows[windowIndex]
    if not window.broken and window.db.visible then
      if window.view == "mode" and window.db.mode == "threat" then
        wantsThreat = true
      elseif dataActive then
        if window.view == "segments" then return true end
        set = data:GetSelectedSet(window.db.segment)
        if set == data.current or set == data.total then
          if window.view == "modes" then return true end
          mode = Skada.Modes:Get(window.db.mode)
          if mode.uptime then return true end
        end
      end
    end
  end
  return wantsThreat and Skada.Threat and Skada.Threat.NeedsUpdates
    and Skada.Threat:NeedsUpdates(now, true) or false
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

-- A segment picked by hand (the meter's segment list, the settings
-- dialog). Mid-fight it is the player's choice, like a mode picked by hand:
-- the segment a combat mode would hand back is dropped, so combat end
-- keeps it.
function UI:ChooseSegment(segment)
  self.db.segment = segment
  if Skada.Data.clientInCombat then self.db.restoreSegment = nil end
  self.manager:NotifyWindowChanged(self)
end

function UI:SelectEntry(entry)
  if not entry then return end
  if entry.modeKey then
    -- Setting the mode also resets the view to it and notifies.
    Skada.Modes:Set(entry.modeKey, self)
  elseif entry.segment ~= nil then
    self:ChooseSegment(entry.segment)
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
  local page = getVisibleRowCount(self.db)
  local maximum = max(0, (self.displayCount or 0) - page)
  local offset = floor(self.scrollOffset or 0)
  if direction > 0 then offset = offset - 1 else offset = offset + 1 end
  local clamped = min(maximum, max(0, offset))
  if clamped == self.scrollOffset then return end
  self.scrollOffset = clamped
  self:PaintRows()
end

function UI:Refresh()
  if not self.frame or self.broken then
    self.hasAnimatingRows = false
    return
  end
  if self.layoutDirty then
    self:ApplyLayout()
    self.layoutDirty = false
  end
  if not self.db.visible then
    self.hasAnimatingRows = false
    return
  end

  local set = Skada.Data:GetSelectedSet(self.db.segment)
  local mode = Skada.Modes:Get(self.db.mode)
  self.paintSet = set
  self.paintMode = mode
  self.paintLive = mode.live
  self.paintSetDuration = nil
  local count = self:BuildDisplay(set, mode)
  self.displayCount = count

  local maximum = count > 0 and self.display[1].value or 1
  if mode.extraField then
    -- the bar scale must fit value + continuation (effective + overheal),
    -- and the widest total is not necessarily the top-sorted row
    local entryIndex, total
    for entryIndex = 1, count do
      total = self.display[entryIndex].value + (self.display[entryIndex].extra or 0)
      if total > maximum then maximum = total end
    end
  end
  if mode.live and Skada.Threat and Skada.Threat.rows and Skada.Threat.rows[1] then
    maximum = Skada.Threat.rows[1].threat or maximum
  end
  if self.view ~= "mode" then maximum = 1 end
  if not maximum or maximum <= 0 then maximum = 1 end
  self.paintMaximum = maximum
  self.currentTitle = self:GetTitle(mode)
  if self.lastTitle ~= self.currentTitle then
    self.lastTitle = self.currentTitle
    self.title:SetText(self.currentTitle)
  end
  if self.actionMenu and self.actionMenu:IsShown() then self.actionMenu:Refresh() end

  self:PaintRows()
end

function UI:InitializeWindow(config)
  local owner = self
  self.db = config

  local frame = CreateFrame("Button", "SkadaBarWindow" .. tostring(config.id), UIParent)
  self.frame = frame
  frame:SetFrameStrata("LOW")
  Style:ApplyMeterWindow(frame, false, Style:GetWindowOpacity(config))
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    delta = getWheelDelta(delta)
    if delta ~= 0 then
      owner.manager:SetActive(owner)
      owner:Scroll(delta)
    end
  end)
  local function goBack()
    owner.manager:SetActive(owner)
    owner.actionMenu:Hide()
    owner:Back()
  end
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnClick", function(_, button)
    button = getClickButton(button)
    if owner.headerWasDragged then
      owner.headerWasDragged = false
      return
    end
    if button == "RightButton" then goBack() end
  end)
  frame:SetScript("OnMouseDown", function(_, button)
    if getClickButton(button) == "LeftButton" then owner.headerWasDragged = false end
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

  -- The title row draws no strip of its own: the window backdrop is the
  -- only background, so the title and its buttons sit directly on it (a
  -- separate tinted band read as a ghost bar at low window opacity).
  Style:ApplyHeader(self)

  local menuButton = UIReport:CreateHeaderButton(header, {
    texture = "Interface\\Icons\\INV_Misc_Gear_01", title = "More actions",
    description = "Settings, logging, reporting, window actions, and reset.",
    click = function()
      owner.manager:SetActive(owner)
      owner.actionMenu:Toggle()
    end,
    rightClick = goBack,
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
      owner.manager:NotifyWindowChanged(owner)
      Skada:MarkDirty()
    end,
    rightClick = goBack,
  })
  self.autoButton = autoButton
  autoButton:SetPoint("RIGHT", menuButton, "LEFT", -Style.HEADER_BUTTON_GAP, 0)

  local modeButton = UIReport:CreateHeaderButton(header, {
    texture = "Interface\\Icons\\Spell_Nature_Lightning", title = "Mode",
    description = "Show the Skada mode list.",
    click = function() owner.manager:SetActive(owner) owner:SetView("modes") end,
    rightClick = goBack,
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
    if owner.headerWasDragged then
      owner.headerWasDragged = false
      return
    end
    if button == "RightButton" then
      goBack()
    else
      owner.manager:SetActive(owner)
      owner.actionMenu:Hide()
      owner:Forward()
    end
  end)
  header:SetScript("OnMouseDown", function() owner.headerWasDragged = false end)

  local headerButtons = { menuButton, autoButton, modeButton }
  self.headerButtons = headerButtons
  local buttonIndex
  for buttonIndex = 1, table_getn(headerButtons) do headerButtons[buttonIndex]:SetAlpha(Style.HEADER_BUTTON_ALPHA) end
  header:SetScript("OnEnter", function(self)
    local buttonIndex
    for buttonIndex = 1, table_getn(headerButtons) do headerButtons[buttonIndex]:SetAlpha(1) end
    local tooltip = getTooltip()
    tooltip:SetOwner(self, "ANCHOR_TOP")
    tooltip:AddLine(owner.currentTitle or config.name or "Skada", 1, 0.5, 0)
    tooltip:AddLine("Left-click forward, right-click back, or drag to move.", 0.8, 0.8, 0.8)
    tooltip:AddLine("This window has independent mode and segment settings.", 0.8, 0.8, 0.8, true)
    tooltip:Show()
  end)
  header:SetScript("OnLeave", function()
    local buttonIndex
    for buttonIndex = 1, table_getn(headerButtons) do headerButtons[buttonIndex]:SetAlpha(Style.HEADER_BUTTON_ALPHA) end
    getTooltip():Hide()
  end)

  local resizeButton = CreateFrame("Button", nil, frame)
  self.resizeButton = resizeButton
  resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  resizeButton:SetWidth(14)
  resizeButton:SetHeight(14)
  resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resizeButton:SetAlpha(0.40)
  resizeButton:RegisterForClicks("RightButtonUp")
  resizeButton:SetScript("OnClick", function(_, button)
    if getClickButton(button) == "RightButton" then goBack() end
  end)
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

-- Every code path that changes a window's settings calls this (meter
-- menus, slash commands, combat switching, the settings dialog), so an
-- open settings page hears that its values or dimming may be stale.
function UI:NotifyWindowChanged(window)
  Skada:Publish("windowSettingsChanged", window)
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
  local windowIndex, window
  for windowIndex = 1, table_getn(self.windows) do
    window = self.windows[windowIndex]
    if string.lower(window.db.name or "") == lowered then return window end
  end
end

function UI:SetActive(window, showSelection)
  if not window or window.broken then return end
  self.activeWindow = window
  if showSelection ~= nil then
    self.visualActive = showSelection and window or nil
  end
  Skada.db.profile.selectedWindowID = window.db.id
  local windowIndex, candidate
  for windowIndex = 1, table_getn(self.windows) do
    candidate = self.windows[windowIndex]
    if not candidate.broken then
      if candidate ~= window and candidate.actionMenu then candidate.actionMenu:Hide() end
      Style:ApplyMeterWindow(candidate.frame, candidate == self.visualActive, Style:GetWindowOpacity(candidate.db))
      Style:ApplyHeader(candidate)
    end
  end
end

function UI:ClearSelectionVisual()
  self.visualActive = nil
  self.activeWindow = nil
  local windowIndex, candidate
  for windowIndex = 1, table_getn(self.windows) do
    candidate = self.windows[windowIndex]
    if not candidate.broken then
      Style:ApplyMeterWindow(candidate.frame, false, Style:GetWindowOpacity(candidate.db))
      Style:ApplyHeader(candidate)
    end
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
  table.insert(self.windows, window)
  self.byID[config.id] = window
  local ok, message = pcall(window.InitializeWindow, window, config)
  if not ok then
    window.broken = true
    Skada:Print("Window " .. tostring(config.id) .. " failed to build: " .. tostring(message))
  end
  return window
end

function UI:CreateNew(name)
  local source = self:GetActive() or self:GetPrimary()
  local profile = Skada.db.profile
  local windowId = profile.nextWindowID or 2
  profile.nextWindowID = windowId + 1
  local config = { id = windowId }
  applyWindowDefaults(config, source and source.db)
  config.name = name and name ~= "" and name or Skada.Modes:Get(config.mode).title
  config.nameIsCustom = name ~= nil and name ~= ""
  config.visible = true
  config.x = (source and source.db.x or 0) + 28
  config.y = (source and source.db.y or 0) - 28
  config.segment = Skada.Data.clientInCombat and "current" or "total"
  if Skada.Modes:Get(config.mode).live then config.segment = "current" end
  -- A copy made mid-fight of a window on its combat mode inherits the way
  -- back too, or it would stay on the combat mode for good.
  if source and source.db.restoreMode then
    config.restoreMode, config.restoreSegment = source.db.restoreMode, source.db.restoreSegment
  end
  table.insert(profile.windows, config)
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
  local replaceVisualSelection = self.visualActive == window
  if window.actionMenu then window.actionMenu:Hide() end
  window.frame:Hide()
  self.byID[window.db.id] = nil
  local windowIndex
  for windowIndex = table_getn(self.windows), 1, -1 do
    if self.windows[windowIndex] == window then table.remove(self.windows, windowIndex) break end
  end
  local configIndex
  for configIndex = table_getn(Skada.db.profile.windows), 1, -1 do
    if Skada.db.profile.windows[configIndex] == window.db then
      table.remove(Skada.db.profile.windows, configIndex)
      break
    end
  end
  self.activeWindow = self:GetPrimary()
  self:SetActive(self.activeWindow, replaceVisualSelection and true or nil)
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

local function applyVisible(window, visible)
  window.db.visible = visible
  if window.frame then
    if visible then window.frame:Show() else window.frame:Hide() end
  end
  if not visible and window.actionMenu then window.actionMenu:Hide() end
  window.layoutDirty = true
end

-- Shows or hides one window: the saved flag, the frame and an open
-- settings page. An explicit choice also forgets that the show/hide-all
-- toggle hid it.
function UI:SetWindowVisible(window, visible)
  if not window then return end
  window.db.hiddenByToggle = nil
  applyVisible(window, visible and true or false)
  self:NotifyWindowChanged(window)
  Skada:MarkDirty()
end

-- Shows or hides every window together: hide all while any is shown, then
-- show back exactly the windows that hid, so a window hidden on purpose
-- stays hidden. Each window keeps its own `visible` flag, so its settings
-- page stays truthful, and the mark rides in its saved settings, so it
-- survives a /reload.
function UI:ToggleAllWindows()
  local anyShown, anyMarked = false, false
  local windowIndex, window
  for windowIndex = 1, table_getn(self.windows) do
    -- A window that failed to build is never shown or hidden below, so
    -- its stale `visible` flag must not count, or every click hides.
    window = self.windows[windowIndex]
    if not window.broken then
      if window.db.visible then anyShown = true end
      if window.db.hiddenByToggle then anyMarked = true end
    end
  end
  for windowIndex = 1, table_getn(self.windows) do
    window = self.windows[windowIndex]
    if not window.broken then
      if anyShown then
        if window.db.visible then
          window.db.hiddenByToggle = true
          applyVisible(window, false)
        end
      else
        -- Nothing marked (every window was hidden one by one): show all.
        if window.db.hiddenByToggle or not anyMarked then applyVisible(window, true) end
        window.db.hiddenByToggle = nil
      end
    end
  end
  self:NotifyWindowChanged()
  Skada:MarkDirty()
  return not anyShown
end

function UI:RefreshAll()
  local windowIndex, window
  local hasAnimations = false
  for windowIndex = 1, table_getn(self.windows) do
    window = self.windows[windowIndex]
    window:Refresh()
    if window.hasAnimatingRows then hasAnimations = true end
    if not window.broken then
      Style:SetButtonActive(window.autoButton, window.db.autoSwitch, 0.20, 1, 0.20)
      if not window.db.visible and window.actionMenu then window.actionMenu:Hide() end
    end
  end

  self.hasActiveAnimations = hasAnimations
end

-- A combat mode is a round trip: the window switches to it when combat
-- starts and comes back to the mode it had when combat ends. (Staying on
-- the combat mode afterwards was a second toggle that asked the same
-- question twice; a window that should always show a mode just sets it.)
--
-- The way back (mode and segment) is saved on the window's own settings,
-- not held at runtime: db.mode already holds the combat mode mid-fight, so a
-- /reload there must still know where to return. The segment rides along
-- because a live combat mode forces "current", which would otherwise
-- silently unpin a window parked on Overall or a saved fight.
function UI:ApplyCombatState(inCombat)
  local db = self.db
  local combatMode = db.combatMode
  local renamed = false
  if inCombat and combatMode and combatMode ~= "" and combatMode ~= db.mode then
    if not db.restoreMode then
      db.restoreMode, db.restoreSegment = db.mode, db.segment
    end
    local _, modeRenamed = Skada.Modes:Set(combatMode, self)
    renamed = modeRenamed
  elseif not inCombat and db.restoreMode then
    local restoreMode, restoreSegment = db.restoreMode, db.restoreSegment
    db.restoreMode, db.restoreSegment = nil, nil
    local _, modeRenamed = Skada.Modes:Set(restoreMode, self)
    renamed = modeRenamed
    if not db.autoSwitch and not Skada.Modes:Get(db.mode).live and restoreSegment ~= nil
        and (type(restoreSegment) ~= "number" or Skada.Data.history[restoreSegment]) then
      db.segment = restoreSegment
    end
  end
  if Skada.Modes:Get(self.db.mode).live then self.db.segment = "current" end
  if not self.db.autoSwitch then return renamed end
  if not Skada.Modes:Get(self.db.mode).live then
    self.db.segment = inCombat and "current" or "total"
  end
  self.detailActor = nil
  self.view = "mode"
  self.scrollOffset = 0
  self.manager:NotifyWindowChanged(self)
  return renamed
end

-- Every window switches at once; an open settings dialog redraws once for
-- the lot (each auto-named window's rename would otherwise rebuild it).
local function applyCombatStateToAll(manager, inCombat)
  local windowIndex, renamed
  renamed = false
  for windowIndex = 1, table_getn(manager.windows) do
    if manager.windows[windowIndex]:ApplyCombatState(inCombat) then renamed = true end
  end
  Skada:MarkDirty()
  if renamed and Skada.OptionsSchema then
    Skada.OptionsSchema:NotifyChanged()
  end
end

function UI:OnCombatState(inCombat)
  local options = Skada.Options
  if not options then return applyCombatStateToAll(self, inCombat) end
  options:BeginBatch()
  -- An error must not leave the dialog's batch open (it would never
  -- redraw again); close it, then let the error surface as before.
  local ok, message = pcall(applyCombatStateToAll, self, inCombat)
  options:EndBatch()
  if not ok then error(message, 0) end
end

function UI:ResetViews(resetSegments)
  local windowIndex, window
  for windowIndex = 1, table_getn(self.windows) do
    window = self.windows[windowIndex]
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
  self:NotifyWindowChanged()
end

function UI:MarkLayouts()
  local windowIndex
  for windowIndex = 1, table_getn(self.windows) do self.windows[windowIndex].layoutDirty = true end
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
      -- The popup can sit unanswered into a pull; an automatic reset never
      -- runs mid-fight, even when accepted then.
      OnAccept = function()
        if Skada.Data.active then
          Skada:Print("A fight is in progress; data not reset.")
          return
        end
        Skada.Data:Reset()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1,
    }
  end

  profile.windows = profile.windows or {}

  WindowConfig.Migrate(profile)

  if table_getn(profile.windows) == 0 then
    local first = { id = 1 }
    applyWindowDefaults(first)
    first.name = Skada.Modes:Get(first.mode).title
    profile.windows[1] = first
  end

  local windowIndex, config, highest, window
  highest = 0
  for windowIndex = 1, table_getn(profile.windows) do
    config = profile.windows[windowIndex]
    config.id = config.id or windowIndex
    config.name = config.name or (config.id == 1 and "Skada" or ("Skada " .. config.id))
    applyWindowDefaults(config)
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

function RenderPolicy:ShouldRebuild(now)
  return Skada.dirty or (UI.NeedsContinuousRefresh and Skada.UI:NeedsContinuousRefresh(now))
end

function RenderPolicy:Rebuild()
  Skada.UI:RefreshAll()
end

function RenderPolicy:ShouldAnimate()
  return Skada.UI.hasActiveAnimations and true or false
end

function RenderPolicy:Animate()
  Skada.UI:AnimateAll()
end

Skada:RegisterRenderPolicy(RenderPolicy)
