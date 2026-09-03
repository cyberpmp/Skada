local env = _G or getfenv(0)
local Skada = env.Skada

-- Public API for the settings dialog. The rendering lives in
-- options.dialog.lua (chrome/sidebar/pane) and options.controls.lua
-- (renderers); this module is the surface other code calls -- slash
-- commands, the minimap button, the window title-bar menu -- plus the
-- selection bookkeeping shared with the on-screen window highlight.
local Options = {
  frame = nil,            -- the dialog root frame, once created
  minimapButton = nil,
  selectedWindow = nil,
}
Skada.Options = Options

local Schema = Skada.OptionsSchema
local Dialog = Skada.OptionsDialog

local table_getn = table.getn

function Options:GetCurrentWindow()
  local window = self.selectedWindow
  if window and window.db and Skada.UI.byID[window.db.id] ~= window then window = nil end
  window = window or (Skada.UI and Skada.UI:GetActive())
  if window then self.selectedWindow = window end
  return window
end

function Options:Open()
  if not Skada.initialized then return end
  Dialog:Open()
  self.frame = Dialog.Frame()
  local window = self:GetCurrentWindow()
  if window then Skada.UI:SetActive(window, true) end
end

function Options:Close()
  Dialog:Close()
end

function Options:IsOpen()
  return Dialog.IsOpen()
end

-- Redraws the open dialog (window list changed, window renamed, mode
-- switched). Safe to call anytime.
function Options:Refresh()
  Dialog:Refresh()
end

function Options:Toggle()
  if Dialog.IsOpen() then
    Dialog:Close()
  else
    self:Open()
  end
end

-- Navigates the dialog to this window's pane and highlights its sidebar row.
-- Each window's own settings resolve entirely from a closure captured on the
-- window at table-build time (see Schema:BuildWindowArgs);
-- `selectedWindow` only drives the on-screen highlight and where the dialog
-- jumps to, not what any control reads or writes.
function Options:SelectWindow(window)
  if not window then return end
  self.selectedWindow = window
  Skada.UI:SetActive(window, true)
  Dialog:Open("window_" .. tostring(window.db.id))
  self.frame = Dialog.Frame()
end

function Options:CycleWindow(delta)
  local windows = Skada.UI.windows
  local count = table_getn(windows)
  if count == 0 then return end
  local current = self:GetCurrentWindow()
  local windowIndex, currentIndex
  for windowIndex = 1, count do
    if windows[windowIndex] == current then currentIndex = windowIndex break end
  end
  currentIndex = (currentIndex or (delta > 0 and 0 or count + 1)) + delta
  if currentIndex > count then currentIndex = 1 elseif currentIndex < 1 then currentIndex = count end
  self:SelectWindow(windows[currentIndex])
end

function Options:CreateMinimapButton()
  if not self.minimapButton then
    self.minimapButton = Skada.MinimapButton:Create()
  end
  return self.minimapButton
end

function Options:Initialize()
  if Minimap then self:CreateMinimapButton() end
end

Skada:RegisterInitializer(function() Options:Initialize() end, "options panel")

Skada:Subscribe("windowListChanged", function()
  Options:GetCurrentWindow() -- self-heals and re-caches selectedWindow if it was deleted
  Schema:NotifyChanged()
end)