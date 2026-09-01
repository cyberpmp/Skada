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
    ", parser misses " .. tostring(Skada.Parser:GetMissCount()) .. ".")
end })

registerSlashCommand({ name = "help", handler = printHelp })

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
