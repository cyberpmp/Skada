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

function Schema.WindowGet(key)
  return function()
    local window = Skada.Options and Skada.Options:GetCurrentWindow()
    return window and window.db[key] or false
  end
end

function Schema.WindowSet(key, needsLayout)
  return function(value)
    local window = Skada.Options and Skada.Options:GetCurrentWindow()
    if not window then return end
    window.db[key] = value
    if needsLayout then window.layoutDirty = true end
    Skada.UI:SyncLegacy(window)
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

function Schema:SegmentChoices()
  local choices = {
    { value = "current", label = "Current fight" },
    { value = "total", label = "Overall" },
  }
  local window = Skada.Options and Skada.Options:GetCurrentWindow()
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

function Schema.VisibleSet()
  return function(value)
    local window = Skada.Options and Skada.Options:GetCurrentWindow()
    if not window then return end
    window.db.visible = value and true or false
    if window.frame then
      if value then window.frame:Show() else window.frame:Hide() end
    end
    window.layoutDirty = true
    Skada.UI:SyncLegacy(window)
    Skada:MarkDirty()
  end
end

function Schema.RenameSet()
  return function(value)
    local window = Skada.Options and Skada.Options:GetCurrentWindow()
    if not window or not value or value == "" then return end
    window.db.name = value
    window.db.nameIsCustom = true
    if window.title then window.title:SetText(value) end
    if Skada.Options.frame and Skada.OptionsShell then
      Skada.OptionsShell.RebuildTree(Skada.Options)
    end
    Skada:MarkDirty()
  end
end

Schema.resetPolicyChoices = {
  { value = "ask", label = "Ask" },
  { value = "yes", label = "Always reset" },
  { value = "no", label = "Never reset" },
}

Schema.groups = {
  { key = "general", label = "General", page = "general" },
  { key = "windows", label = "Windows" },
}

function Schema:WindowNodes()
  local nodes = {}
  local windows = Skada.UI and Skada.UI.windows or {}
  local windowIndex, window
  for windowIndex = 1, table_getn(windows) do
    window = windows[windowIndex]
    table_insert(nodes, {
      key = "windowNode:" .. tostring(window.db.id),
      label = window.db.name or ("Window " .. tostring(window.db.id)),
      page = "window",
      window = window,
    })
  end
  return nodes
end

Schema.pages = {
  general = {
    title = "General",
    rows = {
      { key = "behaviorHeader", widget = "header", label = "Behavior" },
      {
        key = "mergePets", widget = "checkbox",
        label = "Merge pets into owners",
        description = "Combine pet and owner into a single meter entry.",
        get = function() return Skada.db.profile.mergePets and true or false end,
        set = Schema.globalSet("mergePets"),
      },
      {
        key = "trackAll", widget = "checkbox",
        label = "Track all nearby sources",
        description = "Also record damage and healing from units outside your group.",
        get = function() return Skada.db.profile.trackAll and true or false end,
        set = function(value)
          Skada.db.profile.trackAll = value and true or false
          if not value and Skada.Data then Skada.Data:RebuildRoster() end
          Skada:MarkDirty()
        end,
      },
      {
        key = "combatLogging", widget = "checkbox",
        label = "Combat file logging",
        description = "Write WoWCombatLog.txt for Chronicle upload.",
        get = function() return Skada.combatLogging and true or false end,
        set = function(value) Skada:SetCombatLogging(value, true) end,
      },
      {
        key = "minimap", widget = "checkbox",
        label = "Show minimap button",
        description = "Show the Skada button around the minimap.",
        get = function() return Skada.db.profile.minimap.show ~= false end,
        set = function(value)
          Skada.db.profile.minimap.show = value and true or false
          local button = Skada.Options.minimapButton
          if button then
            if value then button:Show() else button:Hide() end
          end
        end,
      },
      { key = "appearanceHeader", widget = "header", label = "Global Appearance" },
      {
        key = "windowBorderStyle", widget = "dropdown",
        label = "Window border style",
        description = "Choose the soft shadow, plain solid edge, or no border used by every window.",
        choices = Skada.UIStyle.WINDOW_BORDER_STYLES,
        get = function()
          if Skada.db.profile.hideWindowBorder then return "none" end
          return Skada.db.profile.windowBorderStyle or "solid"
        end,
        set = function(value)
          Skada.db.profile.windowBorderStyle = value
          Skada.db.profile.hideWindowBorder = value == "none"
          Skada.UI:MarkLayouts()
          Skada:MarkDirty()
        end,
      },
      {
        key = "windowBorderColor", widget = "swatch",
        label = "Window border color",
        description = "Color of the thin window edge used by every window.",
        get = function() return Skada.db.profile.windowBorderColor end,
        set = function(red, green, blue)
          Skada.db.profile.windowBorderColor = { red, green, blue }
          Skada.UI:MarkLayouts()
          Skada:MarkDirty()
        end,
      },
      {
        key = "barTexture", widget = "dropdown",
        label = "Bar texture",
        description = "Texture used for colored fills and their dark backgrounds in every window.",
        choices = Skada.UIStyle.BAR_TEXTURES,
        get = function() return Skada.db.profile.barTexture or "flat" end,
        set = Schema.AppearanceSet("barTexture", false),
      },
      {
        key = "fontName", widget = "dropdown",
        label = "Bar font",
        description = "Font used by every Skada window.",
        choices = Schema.fontChoices,
        get = function() return Skada.db.profile.fontName end,
        set = function(value)
          Skada.db.profile.fontName = value
          Skada.UI:MarkLayouts()
          Skada:MarkDirty()
        end,
      },
      {
        key = "classColors", widget = "checkbox",
        label = "Use class colors",
        description = "Color bars by class in every window; when off, use the custom color below.",
        get = function() return Skada.db.profile.classColors ~= false end,
        set = Schema.globalSet("classColors"),
      },
      {
        key = "barColor", widget = "swatch",
        label = "Custom bar color",
        description = "Bar color used by every window when class colors are off.",
        get = function() return Skada.db.profile.barColor end,
        set = function(red, green, blue) Skada.db.profile.barColor = { red, green, blue } end,
      },
      {
        key = "spellColors", widget = "checkbox",
        label = "Color spell breakdowns",
        description = "Give spell rows distinct colors in every window.",
        get = function() return Skada.db.profile.spellColors ~= false end,
        set = Schema.AppearanceSet("spellColors", false),
      },
      {
        key = "showClassIcons", widget = "checkbox",
        label = "Show class icons",
        description = "Show class icons before player names in every window.",
        get = function() return Skada.db.profile.showClassIcons and true or false end,
        set = Schema.AppearanceSet("showClassIcons", false),
      },
      {
        key = "classColorMenus", widget = "checkbox",
        label = "Class-colored chrome",
        description = "Tint header controls and selected window edges with your class color.",
        get = function() return Skada.db.profile.classColorMenus and true or false end,
        set = Schema.AppearanceSet("classColorMenus", true),
      },
      {
        key = "highlightSelf", widget = "checkbox",
        label = "Highlight my bar",
        description = "Draw a separate colored border around your row in every window.",
        get = function() return Skada.db.profile.highlightSelf and true or false end,
        set = Schema.AppearanceSet("highlightSelf", false),
      },
      {
        key = "highlightSelfColor", widget = "swatch",
        label = "My bar highlight color",
        description = "Border color used to identify your own row in every window.",
        get = function() return Skada.db.profile.highlightSelfColor end,
        set = function(red, green, blue) Skada.db.profile.highlightSelfColor = { red, green, blue } end,
      },
      {
        key = "barBorder", widget = "checkbox",
        label = "Show bar borders",
        description = "Draw a thin border around every visible row in every window.",
        get = function() return Skada.db.profile.barBorder and true or false end,
        set = Schema.AppearanceSet("barBorder", false),
      },
      {
        key = "barBorderColor", widget = "swatch",
        label = "Bar border color",
        description = "Border color used for normal rows in every window.",
        get = function() return Skada.db.profile.barBorderColor end,
        set = function(red, green, blue) Skada.db.profile.barBorderColor = { red, green, blue } end,
      },
      { key = "dataHeader", widget = "header", label = "Data" },
      {
        key = "maxSegments", widget = "slider",
        label = "Saved fights",
        description = "How many finished fights to keep in history. Older fights are dropped.",
        min = 1, max = 50, step = 1,
        format = function(value) return tostring(floor(value)) end,
        get = function() return Skada.db.profile.maxSegments end,
        set = function(value)
          Skada.db.profile.maxSegments = floor(value)
          Skada.Data:TrimHistory()
          Skada:MarkDirty()
        end,
      },
      {
        key = "onlyBossFights", widget = "checkbox",
        label = "Remember boss fights only",
        description = "Keep finished boss fights in the history; other fights are shown live and then discarded.",
        get = function() return Skada.db.profile.onlyBossFights and true or false end,
        set = Schema.globalSet("onlyBossFights"),
      },
      {
        key = "numberFormat", widget = "dropdown",
        label = "Number format",
        description = "How damage and healing totals are abbreviated on bars.",
        choices = {
          { value = "compact", label = "Compact" },
          { value = "compact1", label = "Compact, one decimal" },
          { value = "full", label = "Full numbers" },
        },
        get = function() return Skada.db.profile.numberFormat or "compact" end,
        set = Schema.globalSet("numberFormat"),
      },
      {
        key = "resetData", widget = "action",
        label = "Reset all data",
        description = "Clear the current fight, overall totals, and saved fight history.",
        width = 180,
        onClick = function()
          if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.SKADA_RESET_DATA then
            StaticPopup_Show("SKADA_RESET_DATA")
          else
            Skada.Data:Reset()
          end
        end,
      },
      { key = "policyHeader", widget = "header", label = "Automatic resets" },
      {
        key = "resetOnEnterInstance", widget = "dropdown",
        label = "On entering an instance",
        description = "Reset all data when you zone into an instance.",
        choices = Schema.resetPolicyChoices,
        get = function() return Skada.db.profile.resetOnEnterInstance or "ask" end,
        set = Schema.globalSet("resetOnEnterInstance"),
      },
      {
        key = "resetOnJoinGroup", widget = "dropdown",
        label = "On joining a group",
        description = "Reset all data when you join a party or raid.",
        choices = Schema.resetPolicyChoices,
        get = function() return Skada.db.profile.resetOnJoinGroup or "ask" end,
        set = Schema.globalSet("resetOnJoinGroup"),
      },
      {
        key = "resetOnLeaveGroup", widget = "dropdown",
        label = "On leaving a group",
        description = "Reset all data when you leave the party or raid.",
        choices = Schema.resetPolicyChoices,
        get = function() return Skada.db.profile.resetOnLeaveGroup or "ask" end,
        set = Schema.globalSet("resetOnLeaveGroup"),
      },
    },
  },

  window = {
    title = "Window",
    dynamicTitle = true,
    rows = {
      {
        key = "combatHeader", widget = "header", label = "Combat",
      },
      {
        key = "combatMode", widget = "dropdown",
            label = "Combat mode",
            description = "Mode this window switches to when combat starts. None keeps the current mode.",
            choices = function()
              local choices = { { value = "", label = "None" } }
              local modes = Schema:ModeChoices()
              local modeIndex
              for modeIndex = 1, table_getn(modes) do table_insert(choices, modes[modeIndex]) end
              return choices
            end,
            get = Schema.WindowGet("combatMode"),
            set = function(value)
              Schema.WindowSet("combatMode")(value)
              local window = Skada.Options:GetCurrentWindow()
              if window then window:ApplyCombatState(Skada.Data.clientInCombat) end
            end,
          },
          {
            key = "returnAfterCombat", widget = "checkbox",
            label = "Return after combat",
            description = "With a combat mode set, restore the previous mode when combat ends.",
            get = Schema.WindowGet("returnAfterCombat"),
            set = Schema.WindowSet("returnAfterCombat"),
          },
      {
        key = "designHeader", widget = "header", label = "Design",
      },
          {
            key = "visible", widget = "checkbox",
            label = "Visible",
            description = "Show this meter window.",
            get = Schema.WindowGet("visible"),
            set = Schema.VisibleSet(),
          },
          {
            key = "locked", widget = "checkbox",
            label = "Locked",
            description = "Lock the window: no dragging or resizing.",
            get = Schema.WindowGet("locked"),
            set = Schema.WindowSet("locked", true),
          },
          {
            key = "hideTitle", widget = "checkbox",
            label = "Hide title bar",
            description = "Collapse the window to its bars. The top bar slot then navigates and drags like the title bar, even when no bar is displayed.",
            get = Schema.WindowGet("hideTitle"),
            set = Schema.WindowSet("hideTitle", true),
          },
          {
            key = "name", widget = "editbox",
            label = "Window name",
            description = "Title shown in the window header.",
            get = function()
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              return window and window.db.name or ""
            end,
            set = Schema.RenameSet(),
          },
          {
            key = "width", widget = "slider",
            label = "Width",
            description = "Window width in UI points. The minimum keeps every header control usable.",
            min = Skada.UIStyle.MIN_WINDOW_WIDTH, max = 600, step = 5,
            format = function(value) return floor(value) .. " px" end,
            get = Schema.WindowGet("width"),
            set = Schema.WindowSet("width", true),
          },
          {
            key = "rows", widget = "slider",
            label = "Rows",
            description = "Number of visible meter bars. The window grows or shrinks to fit: title bar + rows x (bar height + spacing) + footer.",
            min = 3, max = 30, step = 1,
            format = function(value) return tostring(floor(value)) end,
            get = Schema.WindowGet("rows"),
            set = Schema.WindowSet("rows", true),
          },
          {
            key = "barHeight", widget = "slider",
            label = "Bar height",
            description = "Height of each meter bar. Together with spacing this is the distance from one bar's top to the next.",
            min = 10, max = 30, step = 1,
            format = function(value) return tostring(floor(value)) .. " px" end,
            get = Schema.WindowGet("barHeight"),
            set = Schema.WindowSet("barHeight", true),
          },
          {
            key = "barSpacing", widget = "slider",
            label = "Bar spacing",
            description = "Gap between meter bars. Bars sit barHeight + spacing apart; the window height follows.",
            min = 0, max = 8, step = 1,
            format = function(value) return tostring(floor(value)) .. " px" end,
            get = Schema.WindowGet("barSpacing"),
            set = Schema.WindowSet("barSpacing", true),
          },
          {
            key = "barAlpha", widget = "slider",
            label = "Bar opacity",
            description = "Transparency of the bar fills. Drag to 0% to hide the fills and keep only names and numbers.",
            min = 0, max = 1, step = 0.02,
            format = function(value) return tostring(floor(value * 100 + 0.5)) .. "%" end,
            get = Schema.WindowGet("barAlpha"),
            set = Schema.WindowSet("barAlpha", true),
          },
          {
            key = "windowOpacity", widget = "slider",
            label = "Window opacity",
            description = "Opacity of this window's background: backdrop, row backs, and title bar. Drag to 0% for a fully transparent window with floating bars.",
            min = 0, max = 1, step = 0.05,
            format = function(value) return tostring(floor(value * 100 + 0.5)) .. "%" end,
            get = function()
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              return window and window.db.windowOpacity or 0.9
            end,
            set = Schema.WindowSet("windowOpacity", true),
          },
          {
            key = "fontSize", widget = "slider",
            label = "Font size",
            description = "Row text size for the selected window.",
            min = 8, max = 22, step = 1,
            format = function(value) return tostring(floor(value)) .. " px" end,
            get = Schema.WindowGet("fontSize"),
            set = Schema.WindowSet("fontSize", true),
          },
      {
        key = "modeHeader", widget = "header", label = "Mode & Segment",
      },
          {
            key = "mode", widget = "dropdown",
            label = "Mode",
            description = "What this window tracks and displays.",
            choices = function() return Schema:ModeChoices() end,
            get = function()
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              return window and window.db.mode or "damage"
            end,
            set = function(value)
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              if not window then return end
              local _, renamed = Skada.Modes:Set(value, window)
              if Skada.Options.frame then
                Skada.Options:RefreshPage()
                if renamed and Skada.OptionsShell then Skada.OptionsShell.RebuildTree(Skada.Options) end
              end
            end,
          },
          {
            key = "segment", widget = "dropdown",
            label = "Segment",
            description = "Which fight the mode reads: current, overall, or a saved fight.",
            choices = function() return Schema:SegmentChoices() end,
            get = function()
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              if not window then return "current" end
              if Skada.Modes:Get(window.db.mode).live then return "current" end
              return window.db.segment or "current"
            end,
            set = function(value)
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              if not window then return end
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
          {
            key = "autoSwitch", widget = "checkbox",
            label = "Automatic segments",
            description = "Switch between Current in combat and Overall out of combat.",
            get = Schema.WindowGet("autoSwitch"),
            set = function(value)
              Schema.WindowSet("autoSwitch")(value)
              local window = Skada.Options:GetCurrentWindow()
              if value and window then window:ApplyCombatState(Skada.Data.clientInCombat) end
              Skada:MarkDirty()
            end,
          },
          {
            key = "snap", widget = "checkbox",
            label = "Snap to edges and windows",
            description = "Align the window to screen edges and other Skada windows on release.",
            get = Schema.WindowGet("snap"),
            set = Schema.WindowSet("snap", false),
          },
          {
            key = "snapDistance", widget = "slider",
            label = "Snap distance",
            description = "How close a dragged window must get to an edge or window before it snaps.",
            min = 0, max = 40, step = 1,
            format = function(value) return tostring(floor(value)) .. " px" end,
            get = Schema.WindowGet("snapDistance"),
            set = Schema.WindowSet("snapDistance", false),
          },
          {
            key = "snapGap", widget = "slider",
            label = "Snap gap",
            description = "Space kept between the window and what it snapped to.",
            min = 0, max = 20, step = 1,
            format = function(value) return tostring(floor(value)) .. " px" end,
            get = Schema.WindowGet("snapGap"),
            set = Schema.WindowSet("snapGap", false),
          },
          {
            key = "snapSize", widget = "checkbox",
            label = "Match size when snapped",
            description = "Adopt the size of the window docked against: stacked windows share a width but keep their own row count, side-by-side windows share a row count but keep their own width.",
            get = Schema.WindowGet("snapSize"),
            set = Schema.WindowSet("snapSize", true),
          },
          {
            key = "deleteWindow", widget = "action",
            label = "Delete this window",
            description = "Remove this meter window after confirmation.",
            width = 180,
            onClick = function()
              local window = Skada.Options and Skada.Options:GetCurrentWindow()
              if window then Skada.UI:RequestDelete(window) end
            end,
          },
    },
  },
}
