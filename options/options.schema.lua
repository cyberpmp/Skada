local Skada = (_G or getfenv(0)).Skada

-- The settings data contract. Every page the dialog shows is one group
-- here: a name, a one-line description, and an ordered set of leaf specs
-- (type, name, desc, get/set, choices, disabled). The dialog and the
-- control renderers never touch profile data themselves.
--
-- Pages follow ownership. General, Appearance and Data hold the profile-wide
-- settings, split by what a player is looking for ("how it behaves", "how it
-- looks", "what it keeps"); each meter window has its own page holding only
-- the keys stored on that window (Defaults.window's keys), in three
-- sections that fit the pane without scrolling: Window, Display, Layout.
-- Appearance is deliberately global: fonts, textures and colors are one look
-- shared by every window, and each window page's subtitle says so.
local Schema = {}
Skada.OptionsSchema = Schema

local floor = math.floor
local type = type
local tostring = tostring
local table_getn = table.getn
local table_insert = table.insert

Schema.fontChoices = {
  { value = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf", label = "Accidental Presidency" },
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

Schema.numberFormatChoices = {
  { value = "compact", label = "Compact" },
  { value = "compact1", label = "Compact, one decimal" },
  { value = "full", label = "Full numbers" },
}

-- A window's page key: the sidebar row, the dialog's selection and the
-- schema group all name a window page this way.
function Schema.WindowPageKey(window)
  return "window_" .. tostring(window.db.id)
end

-- The window whose page `groupKey` names, if it still exists.
function Schema.WindowForPage(groupKey)
  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex, window
  for windowIndex = 1, table_getn(windows) do
    window = windows[windowIndex]
    if Schema.WindowPageKey(window) == groupKey then return window, windowIndex end
  end
end

-- Tells the settings dialog to re-fetch the options table (built fresh on
-- every call) and redraw. Needed whenever the window list, a window's name,
-- or its mode-derived name changes.
function Schema:NotifyChanged()
  local options = Skada.Options
  if options and options.Refresh then options:Refresh() end
end

-- The option renderers call get(), set(value...) and func(). `list` is
-- this schema's usual ordered {value=, label=} choice array.
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

-- Generic per-window get/set factories. Each window gets its own page built
-- fresh by BuildWindowArgs, so `window` is captured directly rather than
-- resolved through a shared "currently selected window".
function Schema.WindowGet(window, key)
  return function() return window.db[key] end
end

function Schema.WindowSet(window, key, needsLayout)
  return function(value)
    window.db[key] = value
    if needsLayout then window.layoutDirty = true end
    Skada.UI:NotifyWindowChanged(window)
    Skada:MarkDirty()
  end
end

function Schema.globalSet(key, transform)
  return function(value)
    Skada.db.profile[key] = transform and transform(value) or value
    Skada:MarkDirty()
  end
end

function Schema.AppearanceSet(key, needsLayout)
  return function(value)
    Skada.db.profile[key] = value
    if needsLayout and Skada.UI then Skada.UI:MarkLayouts() end
    Skada:MarkDirty()
  end
end

-- A profile color stored as {r, g, b}; `needsLayout` re-lays every window
-- (border colors live in the layout pass), otherwise a repaint suffices.
local function colorGet(key)
  return function()
    local color = Skada.db.profile[key]
    return color[1], color[2], color[3]
  end
end

local function colorSet(key, needsLayout)
  return function(red, green, blue)
    Skada.db.profile[key] = { red, green, blue }
    if needsLayout then Skada.UI:MarkLayouts() end
    Skada:MarkDirty()
  end
end

function Schema.VisibleSet(window)
  return function(value) Skada.UI:SetWindowVisible(window, value) end
end

function Schema.RenameSet(window)
  return function(value)
    if not value or value == "" then return end
    window.db.name = value
    window.db.nameIsCustom = true
    if window.title then window.title:SetText(value) end
    Schema:NotifyChanged()
    Skada:MarkDirty()
  end
end

-- Snap distance and gap are stored per window (the snap code reads each
-- window's own, and a new window copies the active one) but edited once,
-- on General: nobody wants a different snap distance per window, and it
-- kept two sliders off every window page. The setter writes every window;
-- the getter reads the primary window.
function Schema.SnapGet(key)
  return function() return Skada.UI:GetPrimary().db[key] end
end

-- Snap distance and gap only apply while some window snaps; snapping
-- itself is switched per window, on each window's page.
function Schema.NoWindowSnaps()
  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex
  for windowIndex = 1, table_getn(windows) do
    if windows[windowIndex].db.snap then return false end
  end
  return true
end

function Schema.SnapSet(key)
  return function(value)
    local windows = Skada.UI and Skada.UI.windows or {}
    local windowIndex
    for windowIndex = 1, table_getn(windows) do
      windows[windowIndex].db[key] = value
    end
    Skada:MarkDirty()
  end
end

-- ---------------------------------------------------------------------------
-- General: how Skada behaves.
-- ---------------------------------------------------------------------------
function Schema:BuildGeneralArgs()
  return {
    trackingHeader = { type = "header", name = "Tracking", order = 1 },
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
      set = function(value)
        Skada.db.profile.trackAll = value and true or false
        if not value and Skada.Data then Skada.Data:RebuildRoster() end
        Skada:MarkDirty()
      end,
    },
    useNampower = {
      type = "toggle", order = 4,
      name = "Use Nampower combat events",
      desc = "Read damage, healing, power, misses, dispels and deaths from Nampower's server events instead of parsing combat chat text. Unavailable when Nampower is not loaded.",
      disabled = function() return not Skada.Nampower.available end,
      get = function() return Skada.db.profile.useNampower ~= false end,
      set = function(value)
        Skada.db.profile.useNampower = value and true or false
        Skada.Nampower:ApplySetting()
        Skada:MarkDirty()
      end,
    },
    clientHeader = { type = "header", name = "Minimap and logging", order = 5 },
    minimap = {
      type = "toggle", order = 6,
      name = "Show minimap button",
      desc = "Show the Skada button around the minimap.",
      get = function() return Skada.db.profile.minimap.show ~= false end,
      set = function(value)
        Skada.db.profile.minimap.show = value and true or false
        local button = Skada.Options.minimapButton
        if button then
          if value then button:Show() else button:Hide() end
        end
      end,
    },
    combatLogging = {
      type = "toggle", order = 7,
      name = "Combat file logging",
      desc = "Write WoWCombatLog.txt for Chronicle upload.",
      get = function() return Skada.combatLogging and true or false end,
      set = function(value) Skada:SetCombatLogging(value, true) end,
    },
    snapHeader = { type = "header", name = "Window snapping", order = 10 },
    snapDistance = {
      type = "range", order = 11,
      name = "Snap distance",
      desc = "How close a dragged window must get to a screen edge or another window before it snaps. Applies to every window; each window's own page turns snapping on or off.",
      min = 0, max = 40, step = 1,
      disabled = Schema.NoWindowSnaps,
      get = Schema.SnapGet("snapDistance"),
      set = Schema.SnapSet("snapDistance"),
    },
    snapGap = {
      type = "range", order = 12,
      name = "Snap gap",
      desc = "Space kept between a snapped window and what it snapped to. Applies to every window.",
      min = 0, max = 20, step = 1,
      disabled = Schema.NoWindowSnaps,
      get = Schema.SnapGet("snapGap"),
      set = Schema.SnapSet("snapGap"),
    },
  }
end

-- ---------------------------------------------------------------------------
-- Appearance: the one look every window shares.
-- ---------------------------------------------------------------------------
function Schema:BuildAppearanceArgs()
  local function borderIsHidden()
    return Skada.UIStyle:GetWindowBorderStyle() == "none"
  end

  return {
    windowsHeader = { type = "header", name = "Windows", order = 1 },
    windowBorderStyle = {
      type = "select", order = 2,
      name = "Window border",
      desc = "A plain solid edge, a soft shadow, or no border, on every window.",
      values = Schema.selectValues(Skada.UIStyle.WINDOW_BORDER_STYLES),
      sorting = Schema.selectSorting(Skada.UIStyle.WINDOW_BORDER_STYLES),
      get = function() return Skada.UIStyle:GetWindowBorderStyle() end,
      set = function(value)
        Skada.db.profile.windowBorderStyle = value
        Skada.UI:MarkLayouts()
        Skada:MarkDirty()
      end,
    },
    windowBorderColor = {
      type = "color", order = 3,
      name = "Border color",
      desc = "Color of the thin window edge.",
      disabled = borderIsHidden,
      get = colorGet("windowBorderColor"),
      set = colorSet("windowBorderColor", true),
    },
    classColorMenus = {
      type = "toggle", order = 4,
      name = "Class-colored chrome",
      desc = "Tint header controls and selected window edges with your class color.",
      get = function() return Skada.db.profile.classColorMenus and true or false end,
      set = Schema.AppearanceSet("classColorMenus", true),
    },

    barsHeader = { type = "header", name = "Bars", order = 10 },
    barTexture = {
      type = "select", order = 11,
      name = "Bar texture",
      desc = "Texture used for colored fills and their dark backgrounds.",
      values = Schema.selectValues(Skada.UIStyle.BAR_TEXTURES),
      sorting = Schema.selectSorting(Skada.UIStyle.BAR_TEXTURES),
      get = function() return Skada.db.profile.barTexture or "flat" end,
      set = Schema.AppearanceSet("barTexture", false),
    },
    fontName = {
      type = "select", order = 12,
      name = "Bar font",
      desc = "Font used by every Skada window. Each window sets its own size.",
      values = Schema.selectValues(Schema.fontChoices),
      sorting = Schema.selectSorting(Schema.fontChoices),
      get = function() return Skada.db.profile.fontName end,
      set = function(value)
        Skada.db.profile.fontName = value
        Skada.UI:MarkLayouts()
        Skada:MarkDirty()
      end,
    },
    numberFormat = {
      type = "select", order = 13,
      name = "Number format",
      desc = "How damage and healing totals are abbreviated on bars.",
      values = Schema.selectValues(Schema.numberFormatChoices),
      sorting = Schema.selectSorting(Schema.numberFormatChoices),
      get = function() return Skada.db.profile.numberFormat or "compact" end,
      set = Schema.globalSet("numberFormat"),
    },
    showClassIcons = {
      type = "toggle", order = 14,
      name = "Show class icons",
      desc = "Show class icons before player names.",
      get = function() return Skada.db.profile.showClassIcons and true or false end,
      set = Schema.AppearanceSet("showClassIcons", false),
    },
    barBorder = {
      type = "toggle", order = 15,
      name = "Bar borders",
      desc = "Draw a thin border around every visible row.",
      get = function() return Skada.db.profile.barBorder and true or false end,
      set = Schema.AppearanceSet("barBorder", false),
    },
    barBorderColor = {
      type = "color", order = 16,
      name = "Bar border color",
      desc = "Border color used for normal rows.",
      disabled = function() return not Skada.db.profile.barBorder end,
      get = colorGet("barBorderColor"),
      set = colorSet("barBorderColor", false),
    },

    colorsHeader = { type = "header", name = "Colors", order = 20 },
    classColors = {
      type = "toggle", order = 21,
      name = "Class colors",
      desc = "Color each player's bar by class. When off, every bar uses the custom color.",
      get = function() return Skada.db.profile.classColors ~= false end,
      set = Schema.globalSet("classColors"),
    },
    barColor = {
      type = "color", order = 22,
      name = "Custom bar color",
      desc = "Bar color used when class colors are off.",
      disabled = function() return Skada.db.profile.classColors ~= false end,
      get = colorGet("barColor"),
      set = colorSet("barColor", false),
    },
    spellColors = {
      type = "toggle", order = 23, newRow = true,
      name = "Color spell breakdowns",
      desc = "Give spell rows distinct colors.",
      get = function() return Skada.db.profile.spellColors ~= false end,
      set = Schema.AppearanceSet("spellColors", false),
    },
    highlightSelf = {
      type = "toggle", order = 24, newRow = true,
      name = "Highlight my bar",
      desc = "Draw a separate colored border around your own row.",
      get = function() return Skada.db.profile.highlightSelf and true or false end,
      set = Schema.AppearanceSet("highlightSelf", false),
    },
    highlightSelfColor = {
      type = "color", order = 25,
      name = "My bar color",
      desc = "Border color used to identify your own row.",
      disabled = function() return not Skada.db.profile.highlightSelf end,
      get = colorGet("highlightSelfColor"),
      set = colorSet("highlightSelfColor", false),
    },
  }
end

-- ---------------------------------------------------------------------------
-- Data: what is kept and when it is cleared.
-- ---------------------------------------------------------------------------
function Schema:BuildDataArgs()
  return {
    historyHeader = { type = "header", name = "Fight history", order = 1 },
    maxSegments = {
      type = "range", order = 2,
      name = "Saved fights",
      desc = "How many finished fights to keep in history. Older fights are dropped.",
      min = 1, max = 50, step = 1,
      -- The setter deletes fights: commit where the drag ends, not every
      -- value it passes on the way.
      commitOnRelease = true,
      get = function() return Skada.db.profile.maxSegments end,
      set = function(value)
        Skada.db.profile.maxSegments = floor(value)
        Skada.Data:TrimHistory()
        Skada:MarkDirty()
      end,
    },
    onlyBossFights = {
      type = "toggle", order = 3,
      name = "Remember boss fights only",
      desc = "Keep finished boss fights in the history; other fights are shown live and then discarded.",
      get = function() return Skada.db.profile.onlyBossFights and true or false end,
      set = Schema.globalSet("onlyBossFights"),
    },
    resetData = {
      type = "execute", order = 4, width = "full",
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
    policyHeader = { type = "header", name = "Automatic resets", order = 10 },
    resetOnEnterInstance = {
      type = "select", order = 11,
      name = "On entering an instance",
      desc = "Reset all data when you zone into an instance.",
      values = Schema.selectValues(Schema.resetPolicyChoices),
      sorting = Schema.selectSorting(Schema.resetPolicyChoices),
      get = function() return Skada.db.profile.resetOnEnterInstance or "ask" end,
      set = Schema.globalSet("resetOnEnterInstance"),
    },
    resetOnJoinGroup = {
      type = "select", order = 12,
      name = "On joining a group",
      desc = "Reset all data when you join a party or raid.",
      values = Schema.selectValues(Schema.resetPolicyChoices),
      sorting = Schema.selectSorting(Schema.resetPolicyChoices),
      get = function() return Skada.db.profile.resetOnJoinGroup or "ask" end,
      set = Schema.globalSet("resetOnJoinGroup"),
    },
    resetOnLeaveGroup = {
      type = "select", order = 13,
      name = "On leaving a group",
      desc = "Reset all data when you leave the party or raid.",
      values = Schema.selectValues(Schema.resetPolicyChoices),
      sorting = Schema.selectSorting(Schema.resetPolicyChoices),
      get = function() return Skada.db.profile.resetOnLeaveGroup or "ask" end,
      set = Schema.globalSet("resetOnLeaveGroup"),
    },
    policyNote = {
      type = "note", order = 14,
      name = "An automatic reset never runs while a fight is in progress.",
    },
  }
end

-- ---------------------------------------------------------------------------
-- One window: only the keys stored on that window.
-- ---------------------------------------------------------------------------

-- Every leaf here is bound to `window` directly (a closure capture), since
-- each meter window gets its own page built fresh by BuildWindowsArgs;
-- there is no shared "currently selected window" for these to resolve.
function Schema:BuildWindowArgs(window)
  local combatModeChoices = function()
    local choices = { { value = "", label = "None" } }
    local modes = Schema:ModeChoices()
    local modeIndex
    for modeIndex = 1, table_getn(modes) do table_insert(choices, modes[modeIndex]) end
    return choices
  end
  local function modeIsLive()
    return Skada.Modes:Get(window.db.mode).live and true or false
  end
  local function snapIsOff()
    return not window.db.snap
  end

  return {
    windowHeader = { type = "header", name = "Window", order = 1 },
    name = {
      type = "input", order = 2,
      name = "Window name",
      desc = "Title shown in the window header. Until renamed, the window is named after its mode.",
      get = function() return window.db.name or "" end,
      set = Schema.RenameSet(window),
    },
    visible = {
      type = "toggle", order = 3,
      name = "Visible",
      desc = "Show this meter window.",
      get = Schema.WindowGet(window, "visible"),
      set = Schema.VisibleSet(window),
    },
    locked = {
      type = "toggle", order = 4,
      name = "Locked",
      desc = "Lock the window: no dragging or resizing.",
      get = Schema.WindowGet(window, "locked"),
      set = Schema.WindowSet(window, "locked", true),
    },
    hideTitle = {
      type = "toggle", order = 5,
      name = "Hide title bar",
      desc = "Collapse the window to its bars. The top bar slot then navigates and drags like the title bar, even when no bar is displayed.",
      get = Schema.WindowGet(window, "hideTitle"),
      set = Schema.WindowSet(window, "hideTitle", true),
    },
    snap = {
      type = "toggle", order = 6, newRow = true,
      name = "Snap to edges and windows",
      desc = "Align the window to screen edges and other Skada windows on release. Snap distance and gap are set once for every window, under General.",
      get = Schema.WindowGet(window, "snap"),
      set = Schema.WindowSet(window, "snap", false),
    },
    snapSize = {
      type = "toggle", order = 7,
      name = "Match size when snapped",
      desc = "Adopt the size of the window docked against: stacked windows share a width but keep their own row count, side-by-side windows share a row count but keep their own width.",
      disabled = snapIsOff,
      get = Schema.WindowGet(window, "snapSize"),
      set = Schema.WindowSet(window, "snapSize", true),
    },

    displayHeader = { type = "header", name = "Display", order = 10 },
    mode = {
      type = "select", order = 11,
      name = "Mode",
      desc = "What this window tracks and displays.",
      values = Schema.selectValues(function() return Schema:ModeChoices() end),
      sorting = Schema.selectSorting(function() return Schema:ModeChoices() end),
      get = function() return window.db.mode or "damage" end,
      set = function(value)
        local _, renamed = Skada.Modes:Set(value, window)
        if renamed then Schema:NotifyChanged() end
      end,
    },
    segment = {
      type = "select", order = 12,
      name = "Segment",
      desc = "Which fight the mode reads: current, overall, or a saved fight. Live modes always read the current fight.",
      disabled = modeIsLive,
      values = Schema.selectValues(function() return Schema:SegmentChoices(window) end),
      sorting = Schema.selectSorting(function() return Schema:SegmentChoices(window) end),
      get = function()
        if modeIsLive() then return "current" end
        return window.db.segment or "current"
      end,
      set = function(value)
        if type(value) == "number" then
          if not Skada.Data.history[value] then return end
        elseif value ~= "total" then
          value = "current"
        end
        window:ChooseSegment(value)
        window:SetView("mode")
      end,
    },
    combatMode = {
      type = "select", order = 13,
      name = "In combat, switch to",
      desc = "Mode this window shows while in combat; it returns to its previous mode when combat ends. None keeps the current mode.",
      values = Schema.selectValues(combatModeChoices),
      sorting = Schema.selectSorting(combatModeChoices),
      get = Schema.WindowGet(window, "combatMode"),
      set = function(value)
        Schema.WindowSet(window, "combatMode")(value)
        window:ApplyCombatState(Skada.Data.clientInCombat)
      end,
    },
    autoSwitch = {
      type = "toggle", order = 14,
      name = "Automatic segments",
      desc = "Switch between Current in combat and Overall out of combat.",
      get = Schema.WindowGet(window, "autoSwitch"),
      set = function(value)
        Schema.WindowSet(window, "autoSwitch")(value)
        if value then window:ApplyCombatState(Skada.Data.clientInCombat) end
        Skada:MarkDirty()
      end,
    },

    layoutHeader = { type = "header", name = "Layout", order = 20 },
    width = {
      type = "range", order = 21,
      name = "Width",
      desc = "Window width in UI points. The minimum keeps every header control usable.",
      min = Skada.UIStyle.MIN_WINDOW_WIDTH, max = 600, step = 5,
      get = Schema.WindowGet(window, "width"),
      set = Schema.WindowSet(window, "width", true),
    },
    rows = {
      type = "range", order = 22,
      name = "Rows",
      desc = "Number of visible meter bars. The window grows or shrinks to fit: title bar + rows x (bar height + spacing) + footer.",
      min = 3, max = 30, step = 1,
      get = Schema.WindowGet(window, "rows"),
      set = Schema.WindowSet(window, "rows", true),
    },
    barHeight = {
      type = "range", order = 23,
      name = "Bar height",
      desc = "Height of each meter bar. Together with spacing this is the distance from one bar's top to the next.",
      min = 8, max = 60, step = 1,
      get = Schema.WindowGet(window, "barHeight"),
      set = Schema.WindowSet(window, "barHeight", true),
    },
    barSpacing = {
      type = "range", order = 24,
      name = "Bar spacing",
      desc = "Gap between meter bars. Bars sit barHeight + spacing apart; the window height follows.",
      min = 0, max = 8, step = 1,
      get = Schema.WindowGet(window, "barSpacing"),
      set = Schema.WindowSet(window, "barSpacing", true),
    },
    fontSize = {
      type = "range", order = 25,
      name = "Font size",
      desc = "Row text size for this window. The font itself is shared by every window: see Appearance.",
      min = 8, max = 22, step = 1,
      get = Schema.WindowGet(window, "fontSize"),
      set = Schema.WindowSet(window, "fontSize", true),
    },
    barAlpha = {
      type = "range", order = 26, isPercent = true,
      name = "Bar opacity",
      desc = "Transparency of the bar fills. Drag to 0% to hide the fills and keep only names and numbers.",
      min = 0, max = 1, step = 0.02,
      get = Schema.WindowGet(window, "barAlpha"),
      set = Schema.WindowSet(window, "barAlpha", true),
    },
    windowOpacity = {
      type = "range", order = 27, isPercent = true,
      name = "Window opacity",
      desc = "Opacity of this window's background: backdrop, row backs, and title bar. Drag to 0% for a fully transparent window with floating bars.",
      min = 0, max = 1, step = 0.05,
      get = function() return window.db.windowOpacity or 0.9 end,
      set = Schema.WindowSet(window, "windowOpacity", true),
    },
    -- Rendered by the dialog's title-row button (top-right of the page,
    -- level with the window's name), not flowed into the page.
    deleteWindow = {
      type = "execute", order = 40, placement = "title",
      name = "Delete window",
      desc = "Remove this meter window after confirmation.",
      func = function() Skada.UI:RequestDelete(window) end,
    },
  }
end

local function windowGroup(window, order)
  return {
    type = "group", order = order,
    name = window.db.name or ("Window " .. tostring(window.db.id)),
    desc = "This window only. Fonts and colors are shared: see Appearance.",
    args = Schema:BuildWindowArgs(window),
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
    args[Schema.WindowPageKey(window)] = windowGroup(window, windowIndex + 1)
  end
  return args
end

-- The three profile-wide pages, in sidebar order (window pages follow):
-- the one list the dialog's sidebar, its page validation and this schema
-- all read.
Schema.PAGES = {
  {
    key = "general", name = "General",
    desc = "How Skada tracks combat and sits in your interface.",
    build = function() return Schema:BuildGeneralArgs() end,
  },
  {
    key = "appearance", name = "Appearance",
    desc = "The look shared by every window: borders, bars, fonts and colors.",
    build = function() return Schema:BuildAppearanceArgs() end,
  },
  {
    key = "data", name = "Data",
    desc = "Which fights are kept and when everything is cleared.",
    build = function() return Schema:BuildDataArgs() end,
  },
}

local pagesByKey = {}
do
  local pageIndex
  for pageIndex = 1, table_getn(Schema.PAGES) do
    pagesByKey[Schema.PAGES[pageIndex].key] = Schema.PAGES[pageIndex]
  end
end

-- Whether `groupKey` names one of the profile-wide pages.
function Schema.IsProfilePage(groupKey)
  return pagesByKey[groupKey] ~= nil
end

-- One page by key: "general", "appearance", "data" or a window page key.
-- The dialog builds only the page it is about to show.
function Schema:BuildGroup(groupKey)
  local page = pagesByKey[groupKey]
  if page then
    return { type = "group", name = page.name, desc = page.desc, args = page.build() }
  end
  local window, windowIndex = Schema.WindowForPage(groupKey)
  if window then return windowGroup(window, windowIndex + 1) end
  return nil
end

function Schema:BuildOptions()
  local args = {}
  local pageIndex, page
  for pageIndex = 1, table_getn(Schema.PAGES) do
    page = Schema.PAGES[pageIndex]
    args[page.key] = {
      type = "group", order = pageIndex,
      name = page.name, desc = page.desc,
      args = page.build(),
    }
  end
  args.windows = {
    type = "group", order = table_getn(Schema.PAGES) + 1, name = "Windows",
    args = Schema:BuildWindowsArgs(),
  }
  return { type = "group", name = "Skada", args = args }
end
