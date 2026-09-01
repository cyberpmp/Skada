local Skada = (_G or getfenv(0)).Skada

local WindowConfig = {}
Skada.WindowConfig = WindowConfig

local table_getn = table.getn

WindowConfig.keys = {
  "visible", "locked", "width", "rows", "barHeight", "barSpacing",
  "fontSize", "barAlpha", "scale", "mode", "segment", "point",
  "relativePoint", "x", "y", "visualVersion", "autoSwitch", "snap",
  "snapDistance", "snapGap", "snapSize",
}

function WindowConfig.ApplyDefaults(target, source)
  local i, key
  for i = 1, table_getn(WindowConfig.keys) do
    key = WindowConfig.keys[i]
    if target[key] == nil then target[key] = source[key] end
  end
  if target.visible == nil then target.visible = true end
  if target.locked == nil then target.locked = false end
  target.width = math.max((Skada.UIStyle and Skada.UIStyle.MIN_WINDOW_WIDTH) or 180, target.width or 240)
  target.rows = target.rows or 10
  target.barHeight = target.barHeight or 18
  if target.barSpacing == nil then target.barSpacing = 2 end
  target.fontSize = target.fontSize or 15
  target.barAlpha = target.barAlpha or 0.90
  target.scale = target.scale or 1
  target.mode = target.mode or "damage"
  target.segment = target.segment or "current"
  if Skada.Modes:Get(target.mode).live then target.segment = "current" end
  target.point = target.point or "CENTER"
  target.relativePoint = target.relativePoint or "CENTER"
  target.x = target.x or 0
  target.y = target.y or 0
  if target.autoSwitch == nil then target.autoSwitch = true end
  if target.snap == nil then target.snap = true end
  if target.snapDistance == nil then target.snapDistance = 12 end
  if target.snapGap == nil or target.snapGap == 4 then target.snapGap = 0 end
  if target.snapSize == nil then target.snapSize = true end
end

function WindowConfig.SyncLegacy(manager, window)
  if window ~= manager:GetPrimary() then return end
  local profile = Skada.db.profile
  local i, key
  for i = 1, table_getn(WindowConfig.keys) do
    key = WindowConfig.keys[i]
    profile[key] = window.db[key]
  end
end

function WindowConfig.Migrate(profile)
  if not profile.visualVersion then
    if profile.width == 230 and profile.barHeight == 17 and profile.barSpacing == 1 then
      profile.width, profile.barHeight, profile.barSpacing = 240, 18, 0
    end
    profile.fontSize, profile.barAlpha, profile.visualVersion = profile.fontSize or 14, profile.barAlpha or 0.78, 2
    if profile.fontSize == 13 then profile.fontSize = 14 end
  end

  if profile.visualVersion < 3 then
    local i, config
    for i = 1, table_getn(profile.windows or {}) do
      config = profile.windows[i]
      if config.fontSize == 14 then config.fontSize = 15 end
      if config.barAlpha == 0.78 then config.barAlpha = 0.92 end
    end
    if profile.fontSize == 14 then profile.fontSize = 15 end
    if profile.barAlpha == 0.78 then profile.barAlpha = 0.92 end
    profile.visualVersion = 3
  end

  if profile.visualVersion < 4 then
    local i, config
    for i = 1, table_getn(profile.windows or {}) do
      config = profile.windows[i]
      if config.barSpacing == 0 then config.barSpacing = 2 end
      if config.barAlpha == 0.92 then config.barAlpha = 0.90 end
    end
    if profile.barSpacing == 0 then profile.barSpacing = 2 end
    if profile.barAlpha == 0.92 then profile.barAlpha = 0.90 end
    profile.visualVersion = 4
  end
end
