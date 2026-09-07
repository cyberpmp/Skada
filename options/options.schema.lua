local Skada = (_G or getfenv(0)).Skada

local Schema = {}
Skada.OptionsSchema = Schema

local floor = math.floor
local type = type
local tostring = tostring
local table_getn = table.getn
local table_insert = table.insert

Schema.fontChoices = {
  { value = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf", label = "Accidental Presidency" },
  { value = "Interface\\AddOns\\Skada\\media\\Expressway.ttf", label = "Expressway" },
  { value = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
  { value = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
  { value = "Fonts\\MORPHEUS.ttf", label = "Morpheus" },
  { value = "Fonts\\SKURRI.ttf", label = "Skurri" },
}

Schema.resetPolicyChoices = {
  { value = "ask", label = "Ask" },
  { value = "yes", label = "Always reset" },
  { value = "no", label = "Never reset" },
}

-- Tells the settings dialog to re-fetch the options table (built fresh by
-- Schema:BuildOptions on every call) and redraw. Needed whenever the window
-- list, a window's name, or its mode-derived name changes.
function Schema:NotifyChanged()
  local options = Skada.Options
  if options and options.Refresh then options:Refresh() end
end

-- The option renderers call get/set/values/sorting as fn(info, ...): an
-- empty bookkeeping table first (the old Ace3 `info` argument, kept as the
-- call signature), then (for set) the new value(s). `list` is this schema's
-- usual ordered {value=, label=} choice array.
local function selectValues(list)
  local values = {}
  local choiceIndex
  for choiceIndex = 1, table_getn(list) do
    values[list[choiceIndex].value] = list[choiceIndex].label
  end
  return values
end

local function selectSorting(list)
  local sorting = {}
  local choiceIndex
  for choiceIndex = 1, table_getn(list) do
    sorting[choiceIndex] = list[choiceIndex].value
  end
  return sorting
end

-- A plain choice array works directly; a function is called fresh each time
-- (dynamic choices such as mode/segment/window lists).
local function resolveChoices(choicesOrFn)
  if type(choicesOrFn) == "function" then return choicesOrFn() end
  return choicesOrFn
end

function Schema.selectValues(choicesOrFn)
  return function() return selectValues(resolveChoices(choicesOrFn)) end
end

function Schema.selectSorting(choicesOrFn)
  return function() return selectSorting(resolveChoices(choicesOrFn)) end
end

function Schema:ModeChoices()
  local choices = {}
  local list = Skada.Modes and Skada.Modes.list or {}
  local modeIndex, mode
  for modeIndex = 1, table_getn(list) do
    mode = list[modeIndex]
    table_insert(choices, { value = mode.key, label = mode.title })
  end
  return choices
end

function Schema:SegmentChoices(window)
  local choices = {
    { value = "current", label = "Current fight" },
    { value = "total", label = "Overall" },
  }
  if window and Skada.Modes:Get(window.db.mode).live then
    return { choices[1] }
  end
  local history = Skada.Data.history or {}
  local historyIndex
  for historyIndex = 1, table_getn(history) do
    table_insert(choices, {
      value = historyIndex,
      label = Skada.Data:GetSegmentLabel(historyIndex),
    })
  end
  return choices
end

-- Generic per-window get/set factories. Each window gets its own tree
-- subgroup built fresh by BuildWindowArgs, so `window` is captured directly
-- rather than resolved through a shared "currently selected window".
function Schema.WindowGet(window, key)
  return function() return window.db[key] end
end

function Schema.WindowSet(window, key, needsLayout)
  return function(info, value)
    window.db[key] = value
    if needsLayout then window.layoutDirty = true end
    Skada.UI:SyncLegacy(window)
    Skada:MarkDirty()
  end
end

function Schema.globalSet(key, transform)
  return function(info, value)
    Skada.db.profile[key] = transform and transform(value) or value
    Skada:MarkDirty()
  end
end

function Schema.AppearanceSet(key, needsLayout)
  return function(info, value)
    Skada.db.profile[key] = value
    if needsLayout and Skada.UI then Skada.UI:MarkLayouts() end
    Skada:MarkDirty()
  end
end

function Schema.VisibleSet(window)
  return function(info, value)
    window.db.visible = value and true or false
    if window.frame then
      if value then window.frame:Show() else window.frame:Hide() end
    end
    window.layoutDirty = true
    Skada.UI:SyncLegacy(window)
    Skada:MarkDirty()
  end
end

function Schema.RenameSet(window)
  return function(info, value)
    if not value or value == "" then return end
    window.db.name = value
    window.db.nameIsCustom = true
    if window.title then window.title:SetText(value) end
    Schema:NotifyChanged()
    Skada:MarkDirty()
  end
end

function Schema:BuildGeneralArgs()
  return {
    behaviorHeader = { type = "header", name = "Behavior", order = 1 },
    mergePets = {
      type = "toggle", order = 2,
      name = "Merge pets into owners",
      desc = "Combine pet and owner into a single meter entry.",
      get = function() return Skada.db.profile.mergePets and true or false end,
      set = Schema.globalSet("mergePets"),
    },
    trackAll = {
      type = "toggle", order = 3,
      name = "Track all nearby sources",
      desc = "Also record damage and healing from units outside your group.",
      get = function() return Skada.db.profile.trackAll and true or false end,
      set = function(info, value)
        Skada.db.profile.trackAll = value and true or false
        if not value and Skada.Data then Skada.Data:RebuildRoster() end
        Skada:MarkDirty()
      end,
    },
    combatLogging = {
      type = "toggle", order = 4,
      name = "Combat file logging",
      desc = "Write WoWCombatLog.txt for Chronicle upload.",
      get = function() return Skada.combatLogging and true or false end,
      set = function(info, value) Skada:SetCombatLogging(value, true) end,
    },
    minimap = {
      type = "toggle", order = 5,
      name = "Show minimap button",
      desc = "Show the Skada button around the minimap.",
      get = function() return Skada.db.profile.minimap.show ~= false end,
      set = function(info, value)
        Skada.db.profile.minimap.show = value and true or false
        local button = Skada.Options.minimapButton
        if button then
          if value then button:Show() else button:Hide() end
        end
      end,
    },
    appearanceHeader = { type = "header", name = "Global Appearance", order = 6 },
    windowBorderStyle = {
      type = "select", order = 7,
      name = "Window border style",
      desc = "Choose the soft shadow, plain solid edge, or no border used by every window.",
      values = Schema.selectValues(Skada.UIStyle.WINDOW_BORDER_STYLES),
      sorting = Schema.selectSorting(Skada.UIStyle.WINDOW_BORDER_STYLES),
      get = function()
        if Skada.db.profile.hideWindowBorder then return "none" end
        return Skada.db.profile.windowBorderStyle or "solid"
      end,
      set = function(info, value)
        Skada.db.profile.windowBorderStyle = value
        Skada.db.profile.hideWindowBorder = value == "none"
        Skada.UI:MarkLayouts()
        Skada:MarkDirty()
      end,
    },
    windowBorderColor = {
      type = "color", order = 8,
      name = "Window border color",
      desc = "Color of the thin window edge used by every window.",
      get = function()
        local color = Skada.db.profile.windowBorderColor
        return color[1], color[2], color[3]
      end,
      set = function(info, red, green, blue)
        Skada.db.profile.windowBorderColor = { red, green, blue }
        Skada.UI:MarkLayouts()
        Skada:MarkDirty()
      end,
    },
    barTexture = {
      type = "select", order = 9,
      name = "Bar texture",
      desc = "Texture used for colored fills and their dark backgrounds in every window.",
      values = Schema.selectValues(Skada.UIStyle.BAR_TEXTURES),
      sorting = Schema.selectSorting(Skada.UIStyle.BAR_TEXTURES),
      get = function() return Skada.db.profile.barTexture or "flat" end,
      set = Schema.AppearanceSet("barTexture", false),
    },
    fontName = {
      type = "select", order = 10,
      name = "Bar font",
      desc = "Font used by every Skada window.",
      values = Schema.selectValues(Schema.fontChoices),
      sorting = Schema.selectSorting(Schema.fontChoices),
      get = function() return Skada.db.profile.fontName end,
      set = function(info, value)
        Skada.db.profile.fontName = value
        Skada.UI:MarkLayouts()
        Skada:MarkDirty()
      end,
    },
    classColors = {
      type = "toggle", order = 11,
      name = "Use class colors",
      desc = "Color bars by class in every window; when off, use the custom color below.",
      get = function() return Skada.db.profile.classColors ~= false end,
      set = Schema.globalSet("classColors"),
    },
    barColor = {
      type = "color", order = 12,
      name = "Custom bar color",
      desc = "Bar color used by every window when class colors are off.",
      get = function()
        local color = Skada.db.profile.barColor
        return color[1], color[2], color[3]
      end,
      set = function(info, red, green, blue)
        Skada.db.profile.barColor = { red, green, blue }
        Skada:MarkDirty()
      end,
    },
    spellColors = {
      type = "toggle", order = 13,
      name = "Color spell breakdowns",
      desc = "Give spell rows distinct colors in every window.",
      get = function() return Skada.db.profile.spellColors ~= false end,
      set = Schema.AppearanceSet("spellColors", false),
    },
    showClassIcons = {
      type = "toggle", order = 14,
      name = "Show class icons",
      desc = "Show class icons before player names in every window.",
      get = function() return Skada.db.profile.showClassIcons and true or false end,
      set = Schema.AppearanceSet("showClassIcons", false),
    },
    classColorMenus = {
      type = "toggle", order = 15,
      name = "Class-colored chrome",
      desc = "Tint header controls and selected window edges with your class color.",
      get = function() return Skada.db.profile.classColorMenus and true or false end,
      set = Schema.AppearanceSet("classColorMenus", true),
    },
    highlightSelf = {
      type = "toggle", order = 16,
      name = "Highlight my bar",
      desc = "Draw a separate colored border around your row in every window.",
      get = function() return Skada.db.profile.highlightSelf and true or false end,
      set = Schema.AppearanceSet("highlightSelf", false),
    },
    highlightSelfColor = {
      type = "color", order = 17,
      name = "My bar highlight color",
      desc = "Border color used to identify your own row in every window.",
      get = function()
        local color = Skada.db.profile.highlightSelfColor
        return color[1], color[2], color[3]
      end,
      set = function(info, red, green, blue)
        Skada.db.profile.highlightSelfColor = { red, green, blue }
        Skada:MarkDirty()
      end,
    },
    barBorder = {
      type = "toggle", order = 18,
      name = "Show bar borders",
      desc = "Draw a thin border around every visible row in every window.",
      get = function() return Skada.db.profile.barBorder and true or false end,
      set = Schema.AppearanceSet("barBorder", false),
    },
    barBorderColor = {
      type = "color", order = 19,
      name = "Bar border color",
      desc = "Border color used for normal rows in every window.",
      get = function()
        local color = Skada.db.profile.barBorderColor
        return color[1], color[2], color[3]
      end,
      set = function(info, red, green, blue)
        Skada.db.profile.barBorderColor = { red, green, blue }
        Skada:MarkDirty()
      end,
    },
    dataHeader = { type = "header", name = "Data", order = 20 },
    maxSegments = {
      type = "range", order = 21,
      name = "Saved fights",
      desc = "How many finished fights to keep in history. Older fights are dropped.",
      min = 1, max = 50, step = 1,
      get = function() return Skada.db.profile.maxSegments end,
      set = function(info, value)
        Skada.db.profile.maxSegments = floor(value)
        Skada.Data:TrimHistory()
        Skada:MarkDirty()
      end,
    },
    onlyBossFights = {
      type = "toggle", order = 22,
      name = "Remember boss fights only",
      desc = "Keep finished boss fights in the history; other fights are shown live and then discarded.",
      get = function() return Skada.db.profile.onlyBossFights and true or false end,
      set = Schema.globalSet("onlyBossFights"),
    },
    numberFormat = {
      type = "select", order = 23,
      name = "Number format",
      desc = "How damage and healing totals are abbreviated on bars.",
      values = { compact = "Compact", compact1 = "Compact, one decimal", full = "Full numbers" },
      sorting = { "compact", "compact1", "full" },
      get = function() return Skada.db.profile.numberFormat or "compact" end,
      set = Schema.globalSet("numberFormat"),
    },
    resetData = {
      type = "execute", order = 24, width = "full",
      name = "Reset all data",
      desc = "Clear the current fight, overall totals, and saved fight history.",
      func = function()
        if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.SKADA_RESET_DATA then
          StaticPopup_Show("SKADA_RESET_DATA")
        else
          Skada.Data:Reset()
        end
      end,
    },
    policyHeader = { type = "header", name = "Automatic resets", order = 25 },
    resetOnEnterInstance = {
      type = "select", order = 26,
      name = "On entering an instance",
      desc = "Reset all data when you zone into an instance.",
      values = Schema.selectValues(Schema.resetPolicyChoices),
      sorting = Schema.selectSorting(Schema.resetPolicyChoices),
      get = function() return Skada.db.profile.resetOnEnterInstance or "ask" end,
      set = Schema.globalSet("resetOnEnterInstance"),
    },
    resetOnJoinGroup = {
      type = "select", order = 27,
      name = "On joining a group",
      desc = "Reset all data when you join a party or raid.",
      values = Schema.selectValues(Schema.resetPolicyChoices),
      sorting = Schema.selectSorting(Schema.resetPolicyChoices),
      get = function() return Skada.db.profile.resetOnJoinGroup or "ask" end,
      set = Schema.globalSet("resetOnJoinGroup"),
    },
    resetOnLeaveGroup = {
      type = "select", order = 28,
      name = "On leaving a group",
      desc = "Reset all data when you leave the party or raid.",
      values = Schema.selectValues(Schema.resetPolicyChoices),
      sorting = Schema.selectSorting(Schema.resetPolicyChoices),
      get = function() return Skada.db.profile.resetOnLeaveGroup or "ask" end,
      set = Schema.globalSet("resetOnLeaveGroup"),
    },
  }
end

-- Every leaf here is bound to `window` directly (a closure capture), since
-- each meter window gets its own permanent tree subgroup built fresh by
-- BuildWindowsArgs; there is no shared "currently selected window" for these
-- to resolve.
function Schema:BuildWindowArgs(window)
  local combatModeChoices = function()
    local choices = { { value = "", label = "None" } }
    local modes = Schema:ModeChoices()
    local modeIndex
    for modeIndex = 1, table_getn(modes) do table_insert(choices, modes[modeIndex]) end
    return choices
  end

  return {
    combatHeader = { type = "header", name = "Combat", order = 1 },
    combatMode = {
      type = "select", order = 2,
      name = "Combat mode",
      desc = "Mode this window switches to when combat starts. None keeps the current mode.",
      values = Schema.selectValues(combatModeChoices),
      sorting = Schema.selectSorting(combatModeChoices),
      get = Schema.WindowGet(window, "combatMode"),
      set = function(info, value)
        Schema.WindowSet(window, "combatMode")(info, value)
        window:ApplyCombatState(Skada.Data.clientInCombat)
      end,
    },
    returnAfterCombat = {
      type = "toggle", order = 3,
      name = "Return after combat",
      desc = "With a combat mode set, restore the previous mode when combat ends.",
      get = Schema.WindowGet(window, "returnAfterCombat"),
      set = Schema.WindowSet(window, "returnAfterCombat"),
    },
    designHeader = { type = "header", name = "Design", order = 4 },
    visible = {
      type = "toggle", order = 5,
      name = "Visible",
      desc = "Show this meter window.",
      get = Schema.WindowGet(window, "visible"),
      set = Schema.VisibleSet(window),
    },
    locked = {
      type = "toggle", order = 6,
      name = "Locked",
      desc = "Lock the window: no dragging or resizing.",
      get = Schema.WindowGet(window, "locked"),
      set = Schema.WindowSet(window, "locked", true),
    },
    hideTitle = {
      type = "toggle", order = 7,
      name = "Hide title bar",
      desc = "Collapse the window to its bars. The top bar slot then navigates and drags like the title bar, even when no bar is displayed.",
      get = Schema.WindowGet(window, "hideTitle"),
      set = Schema.WindowSet(window, "hideTitle", true),
    },
    name = {
      type = "input", order = 8,
      name = "Window name",
      desc = "Title shown in the window header.",
      get = function() return window.db.name or "" end,
      set = Schema.RenameSet(window),
    },
    width = {
      type = "range", order = 9,
      name = "Width (px)",
      desc = "Window width in UI points. The minimum keeps every header control usable.",
      min = Skada.UIStyle.MIN_WINDOW_WIDTH, max = 600, step = 5,
      get = Schema.WindowGet(window, "width"),
      set = Schema.WindowSet(window, "width", true),
    },
    rows = {
      type = "range", order = 10,
      name = "Rows",
      desc = "Number of visible meter bars. The window grows or shrinks to fit: title bar + rows x (bar height + spacing) + footer.",
      min = 3, max = 30, step = 1,
      get = Schema.WindowGet(window, "rows"),
      set = Schema.WindowSet(window, "rows", true),
    },
    barHeight = {
      type = "range", order = 11,
      name = "Bar height (px)",
      desc = "Height of each meter bar. Together with spacing this is the distance from one bar's top to the next.",
      min = 8, max = 60, step = 1,
      get = Schema.WindowGet(window, "barHeight"),
      set = Schema.WindowSet(window, "barHeight", true),
    },
    barSpacing = {
      type = "range", order = 12,
      name = "Bar spacing (px)",
      desc = "Gap between meter bars. Bars sit barHeight + spacing apart; the window height follows.",
      min = 0, max = 8, step = 1,
      get = Schema.WindowGet(window, "barSpacing"),
      set = Schema.WindowSet(window, "barSpacing", true),
    },
    barAlpha = {
      type = "range", order = 13, isPercent = true,
      name = "Bar opacity",
      desc = "Transparency of the bar fills. Drag to 0% to hide the fills and keep only names and numbers.",
      min = 0, max = 1, step = 0.02,
      get = Schema.WindowGet(window, "barAlpha"),
      set = Schema.WindowSet(window, "barAlpha", true),
    },
    windowOpacity = {
      type = "range", order = 14, isPercent = true,
      name = "Window opacity",
      desc = "Opacity of this window's background: backdrop, row backs, and title bar. Drag to 0% for a fully transparent window with floating bars.",
      min = 0, max = 1, step = 0.05,
      get = function() return window.db.windowOpacity or 0.9 end,
      set = Schema.WindowSet(window, "windowOpacity", true),
    },
    fontSize = {
      type = "range", order = 15,
      name = "Font size (px)",
      desc = "Row text size for this window.",
      min = 8, max = 22, step = 1,
      get = Schema.WindowGet(window, "fontSize"),
      set = Schema.WindowSet(window, "fontSize", true),
    },
    modeHeader = { type = "header", name = "Mode & Segment", order = 16 },
    mode = {
      type = "select", order = 17,
      name = "Mode",
      desc = "What this window tracks and displays.",
      values = Schema.selectValues(function() return Schema:ModeChoices() end),
      sorting = Schema.selectSorting(function() return Schema:ModeChoices() end),
      get = function() return window.db.mode or "damage" end,
      set = function(info, value)
        local _, renamed = Skada.Modes:Set(value, window)
        if renamed then Schema:NotifyChanged() end
      end,
    },
    segment = {
      type = "select", order = 18,
      name = "Segment",
      desc = "Which fight the mode reads: current, overall, or a saved fight.",
      values = Schema.selectValues(function() return Schema:SegmentChoices(window) end),
      sorting = Schema.selectSorting(function() return Schema:SegmentChoices(window) end),
      get = function()
        if Skada.Modes:Get(window.db.mode).live then return "current" end
        return window.db.segment or "current"
      end,
      set = function(info, value)
        if value == "total" then
          window.db.segment = "total"
        elseif type(value) == "number" then
          if not Skada.Data.history[value] then return end
          window.db.segment = value
        else
          window.db.segment = "current"
        end
        Skada.DataNavigation:OnModeChanged(window)
        Skada:MarkDirty()
      end,
    },
    autoSwitch = {
      type = "toggle", order = 19,
      name = "Automatic segments",
      desc = "Switch between Current in combat and Overall out of combat.",
      get = Schema.WindowGet(window, "autoSwitch"),
      set = function(info, value)
        Schema.WindowSet(window, "autoSwitch")(info, value)
        if value then window:ApplyCombatState(Skada.Data.clientInCombat) end
        Skada:MarkDirty()
      end,
    },
    snap = {
      type = "toggle", order = 20,
      name = "Snap to edges and windows",
      desc = "Align the window to screen edges and other Skada windows on release.",
      get = Schema.WindowGet(window, "snap"),
      set = Schema.WindowSet(window, "snap", false),
    },
    snapDistance = {
      type = "range", order = 21,
      name = "Snap distance (px)",
      desc = "How close a dragged window must get to an edge or window before it snaps.",
      min = 0, max = 40, step = 1,
      get = Schema.WindowGet(window, "snapDistance"),
      set = Schema.WindowSet(window, "snapDistance", false),
    },
    snapGap = {
      type = "range", order = 22,
      name = "Snap gap (px)",
      desc = "Space kept between the window and what it snapped to.",
      min = 0, max = 20, step = 1,
      get = Schema.WindowGet(window, "snapGap"),
      set = Schema.WindowSet(window, "snapGap", false),
    },
    snapSize = {
      type = "toggle", order = 23,
      name = "Match size when snapped",
      desc = "Adopt the size of the window docked against: stacked windows share a width but keep their own row count, side-by-side windows share a row count but keep their own width.",
      get = Schema.WindowGet(window, "snapSize"),
      set = Schema.WindowSet(window, "snapSize", true),
    },
    deleteWindow = {
      type = "execute", order = 24, width = "full",
      name = "Delete this window",
      desc = "Remove this meter window after confirmation.",
      func = function() Skada.UI:RequestDelete(window) end,
    },
  }
end

-- The Windows node holds one nested group per meter window and no rows of
-- its own: in the sidebar it is a header, and new windows come from the
-- plus button on that row (options.dialog.lua), not from a page.
function Schema:BuildWindowsArgs()
  local args = {}
  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex, window
  for windowIndex = 1, table_getn(windows) do
    window = windows[windowIndex]
    args["window_" .. tostring(window.db.id)] = {
      type = "group", order = windowIndex + 1,
      name = window.db.name or ("Window " .. tostring(window.db.id)),
      args = Schema:BuildWindowArgs(window),
    }
  end
  return args
end

function Schema:BuildOptions()
  return {
    type = "group",
    name = "Skada",
    args = {
      general = {
        type = "group", order = 1, name = "General",
        args = Schema:BuildGeneralArgs(),
      },
      windows = {
        type = "group", order = 2, name = "Windows",
        args = Schema:BuildWindowsArgs(),
      },
    },
  }
end
