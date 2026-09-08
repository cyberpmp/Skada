local Skada = (_G or getfenv(0)).Skada

local string_match = Skada.Common.Match

local string_lower = string.lower
local table_getn = table.getn

local commandByName = {}

local function registerSlashCommand(entry)
  commandByName[entry.name] = entry
  local aliasIndex
  if entry.aliases then
    for aliasIndex = 1, table_getn(entry.aliases) do
      commandByName[entry.aliases[aliasIndex]] = entry
    end
  end
end

local function getActiveWindow()
  return Skada.UI and Skada.UI:GetActive()
end

local function setWindowVisibility(visible, window)
  if not window then return end
  window.db.visible = visible and true or false
  if window.frame then
    if visible then window.frame:Show() else window.frame:Hide() end
  end
  window.layoutDirty = true
  Skada.UI:SyncLegacy(window)
  Skada:MarkDirty()
end

local function printHelp()
  Skada:Print("/skada (or /skada config) opens the settings panel.")
  Skada:Print("  /skada center")
  Skada:Print("  /skada status")
  Skada:Print("  /skada help")
end

registerSlashCommand({ name = "config", aliases = { "settings", "options" }, handler = function()
  if Skada.Options then Skada.Options:Open() end
end })

registerSlashCommand({ name = "center", handler = function()
  local window = getActiveWindow()
  if not window then return end
  window.db.point, window.db.relativePoint = "CENTER", "CENTER"
  window.db.x, window.db.y = 0, 0
  setWindowVisibility(true, window)
  window:ApplyLayout()
  Skada:Print("Window " .. window.db.id .. " centered.")
end })

registerSlashCommand({ name = "status", handler = function()
  local currentSegment = Skada.Data.current
  Skada:Print("Segment: " .. (Skada.Data.active and "active" or "idle") ..
    ", damage " .. Skada:FormatNumber(currentSegment.damage) ..
    ", parser misses " .. tostring(Skada.Parser:GetMissCount()) ..
    ", source " .. Skada.Nampower:GetStatusText() .. ".")
end })

registerSlashCommand({ name = "help", handler = printHelp })

-- TEMPORARY diagnostic for the settings dialog's dead sidebar on the OctoWoW
-- client: dumps how the engine sees each layer of the dialog plus what is
-- under the cursor. Run it with the mouse over a sidebar row. Remove once the
-- hit-testing gap is understood and fixed.
local function describeFrame(label, frame)
  if not frame then
    Skada:Print(label .. ": nil")
    return
  end
  local function formatNumber(getter)
    local value = getter and getter(frame)
    if value == nil then return "nil" end
    return string.format("%.0f", value)
  end
  -- The engine gates rendering AND hit-testing on a resolved rect: L/T nil or
  -- scale 0 means "unpositioned", which renders in a fallback spot and takes
  -- no clicks. numPts is how many anchors the frame actually has.
  local numPoints = frame.GetNumPoints and frame:GetNumPoints()
  -- strata/lvl/parent: what decides draw and hit-test order. Every frame in
  -- the dialog must share the root's strata and out-level its parent, or the
  -- root's backdrop covers it and the root takes its clicks.
  local parent = frame.GetParent and frame:GetParent()
  local scale = frame.GetEffectiveScale and frame:GetEffectiveScale()
  Skada:Print(string.format("%s %s strata=%s lvl=%s parent=%s L=%s T=%s W=%s H=%s scale=%s pts=%s mouse=%s over=%s",
    label, frame:GetName() or "-",
    tostring(frame.GetFrameStrata and frame:GetFrameStrata()),
    formatNumber(frame.GetFrameLevel),
    parent and (parent:GetName() or "unnamed") or "nil",
    formatNumber(frame.GetLeft), formatNumber(frame.GetTop),
    formatNumber(frame.GetWidth), formatNumber(frame.GetHeight),
    scale and string.format("%.2f", scale) or "nil",
    tostring(numPoints), tostring((frame:IsMouseEnabled())),
    tostring(frame.IsMouseOver and frame:IsMouseOver())))
end

registerSlashCommand({ name = "uiprobe", handler = function()
  local dialog = Skada.OptionsDialog and Skada.OptionsDialog.Frame()
  if not dialog or not dialog:IsShown() then
    Skada:Print("uiprobe: open the settings first")
    return
  end
  describeFrame("dialog", dialog)
  describeFrame("sidebar", dialog.sidebar)
  local sidebarRowIndex
  if dialog.sidebar and dialog.sidebar.rows then
    for sidebarRowIndex = 1, table.getn(dialog.sidebar.rows) do
      describeFrame("row" .. sidebarRowIndex, dialog.sidebar.rows[sidebarRowIndex])
    end
  end
  describeFrame("pane", dialog.pane)
  describeFrame("scrollframe", dialog.scrollframe)
  describeFrame("scrollchild", dialog.content)
  if dialog.content and dialog.controls then
    Skada:Print(string.format("pane: controls=%s childW=%s childH=%s",
      table.getn(dialog.controls),
      tostring(dialog.content.GetWidth and dialog.content:GetWidth()),
      tostring(dialog.content.GetHeight and dialog.content:GetHeight())))
  end
  if dialog.scrollframe then
    local sf = dialog.scrollframe
    local child = sf.GetScrollChild and sf:GetScrollChild()
    Skada:Print(string.format("scroll: childOK=%s vscroll=%s range=%s",
      tostring(child == dialog.content),
      sf.GetVerticalScroll and tostring((sf:GetVerticalScroll())) or "nil",
      sf.GetVerticalScrollRange and tostring((sf:GetVerticalScrollRange())) or "nil"))
  end
  local focus = GetMouseFocus and GetMouseFocus()
  Skada:Print("focus: " .. tostring(focus and (focus:GetName() or "unnamed")))
  if GetMouseFoci then
    local foci = GetMouseFoci()
    local names = {}
    local fociIndex
    for fociIndex = 1, table.getn(foci) do
      table.insert(names, foci[fociIndex]:GetName() or "unnamed")
    end
    Skada:Print("foci: " .. table.concat(names, ", "))
  end
  local cursorX, cursorY = GetCursorPosition()
  Skada:Print(string.format("cursor %.0f,%.0f uiscale %.2f", cursorX or 0, cursorY or 0, UIParent:GetEffectiveScale() or 0))
end })

local function handleSlashCommand(message)
  message = message or ""
  local command, argument = string_match(message, "^%s*(%S*)%s*(.-)%s*$")
  command = string_lower(command or "")
  argument = argument or ""

  if command == "" then
    if Skada.Options then Skada.Options:Open() end
    return
  end

  local entry = commandByName[command]
  if entry then
    entry.handler(argument)
  else
    printHelp()
  end
end

SLASH_SKADA1 = "/skada"
SLASH_SKADA2 = "/sk"
SlashCmdList.SKADA = handleSlashCommand
