local Skada = (_G or getfenv(0)).Skada

local WindowConfig = {}
Skada.WindowConfig = WindowConfig

local floor = math.floor
local max = math.max
local pairs = pairs
local table_getn = table.getn
local tonumber = tonumber

local WINDOW_DEFAULTS = Skada.Defaults.window

function WindowConfig.GetVisibleRowCount(config)
  return max(1, floor(tonumber(config and config.rows) or 1))
end

-- Fills every window setting `target` has not stored: from `source` (the
-- active window's settings, when a new window copies it) or else from
-- Defaults.window.
function WindowConfig.ApplyDefaults(target, source)
  -- A named window that never stored whether its name is its own: a name
  -- that is not a mode title was typed by the player.
  if target.nameIsCustom == nil and target.name then
    target.nameIsCustom = not Skada.Modes:IsTitle(target.name)
  end
  local key, default
  for key, default in pairs(WINDOW_DEFAULTS) do
    if target[key] == nil and source then target[key] = source[key] end
    if target[key] == nil then target[key] = default end
  end
  target.width = max(Skada.UIStyle.MIN_WINDOW_WIDTH, target.width)
  if Skada.Modes:Get(target.mode).live then target.segment = "current" end
end

-- The saved-profile format version (the field keeps its historical name).
local PROFILE_VERSION = 8

-- One-time conversions of saved profiles, oldest first. A fresh profile
-- starts at the current version. Profiles older than 2.0 (version 4 and
-- below, or none) skip straight to the 2.0-era steps: what those early
-- steps did was nudge old default values, which nothing depends on.
function WindowConfig.Migrate(profile)
  local windows = profile.windows or {}
  local windowIndex, config
  if not profile.visualVersion then
    profile.visualVersion = table_getn(windows) == 0 and PROFILE_VERSION or 4
  end

  -- The window border became a style; the old on/off flag picks it.
  if profile.visualVersion < 5 then
    profile.windowBorderStyle = profile.hideWindowBorder and "none" or "solid"
    profile.visualVersion = 5
  end

  -- 2.0.3 dropped the spacing after the last bar from the window height,
  -- and headless windows grew a top inset. Snapped windows are stored by
  -- their bottom-left corner, so a shorter window would open a seam under
  -- the one docked above it. Re-deriving the row count from the pixel
  -- height the window was saved with keeps every window at its old size.
  if profile.visualVersion < 6 then
    local Style = Skada.UIStyle
    for windowIndex = 1, table_getn(windows) do
      config = windows[windowIndex]
      local rows, barHeight, barSpacing = tonumber(config.rows), tonumber(config.barHeight), tonumber(config.barSpacing)
      if config.point == "BOTTOMLEFT" and rows and barHeight and barSpacing and barHeight + barSpacing > 0 then
        local savedHeight = (config.hideTitle and 0 or Style.HEADER_HEIGHT)
          + rows * (barHeight + barSpacing) + Style.FOOTER_HEIGHT
        config.rows = Style:GetRowsForHeight(config, savedHeight)
      end
    end
    profile.visualVersion = 6
  end

  -- Snap distance and gap became one setting for every window, edited on
  -- General, which reads the primary window. Older profiles may hold a
  -- different hidden value per window; give every window the primary's so
  -- the slider tells the truth. The retired default gap of 4 becomes 0.
  if profile.visualVersion < 7 then
    local primary = windows[1]
    if primary then
      local distance, gap = primary.snapDistance, primary.snapGap
      if gap == 4 then gap = 0 end
      for windowIndex = 1, table_getn(windows) do
        config = windows[windowIndex]
        config.snapDistance, config.snapGap = distance, gap
      end
    end
    profile.visualVersion = 7
  end

  -- The profile used to mirror the first window's settings for code that
  -- predated multiple windows, and carried flags since retired. Each
  -- window owns its settings now; drop the copies and the retired flags.
  if profile.visualVersion < 8 then
    local key
    for key in pairs(WINDOW_DEFAULTS) do profile[key] = nil end
    profile.hideWindowBorder = nil
    profile.updateRate, profile.smoothBars, profile.barSpeed = nil, nil, nil
    profile.returnAfterCombat = nil
    for windowIndex = 1, table_getn(windows) do
      config = windows[windowIndex]
      config.visualVersion = nil
      config.returnAfterCombat = nil
    end
    profile.visualVersion = 8
  end
end
