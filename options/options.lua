local Skada = (_G or getfenv(0)).Skada

local Options = {
  frame = nil,
  minimapButton = nil,
  selectedWindow = nil,
  treeRows = nil,
  pageCache = {},
}
Skada.Options = Options

local Common = Skada.Common
local Widgets = Skada.OptionsWidgets
local Shell = Skada.OptionsShell
local Style = Skada.UIStyle

local table_getn = table.getn

local CONTENT_WIDTH = 400

function Options:GetCurrentWindow()
  local window = self.selectedWindow
  if window and window.db and Skada.UI.byID[window.db.id] ~= window then window = nil end
  window = window or (Skada.UI and Skada.UI:GetActive())
  if window then self.selectedWindow = window end
  return window
end

function Options:SelectWindow(window)
  if not window then return end
  self.selectedWindow = window
  Skada.UI:SetActive(window, true)
  if self.frame then
    Shell.ShowPage(self, "window")
    Shell.UpdateTreeSelection(self)
    Shell.RefreshPage(self)
  end
end

function Options:OpenPage(pageKey)
  if not self.frame then return end
  Shell.ShowPage(self, pageKey)
end

function Options:RefreshPage()
  if not self.frame then return end
  Shell.RefreshPage(self)
end

function Options:CycleWindow(delta)
  local windows = Skada.UI.windows
  local count = table_getn(windows)
  if count == 0 then return end
  local current = self:GetCurrentWindow()
  local i, index
  for i = 1, count do
    if windows[i] == current then index = i break end
  end
  index = (index or (delta > 0 and 0 or count + 1)) + delta
  if index > count then index = 1 elseif index < 1 then index = count end
  self:SelectWindow(windows[index])
end

function Options:BuildPanel()
  self.controls = self.controls or {}
  self.kit = Widgets.CreateKit(self.controls, CONTENT_WIDTH - 16)
  Shell.Build(self)
end

function Options:Open()
  if not Skada.initialized then return end
  if not self.frame then self:BuildPanel() end
  local window = self:GetCurrentWindow()
  Shell.RebuildTree(self)
  if not self.currentPage then
    self:OpenPage("general")
  else
    self:OpenPage(self.currentPage)
  end
  Shell.RefreshPage(self)
  if window then Skada.UI:SetActive(window, true) end
  self.frame:Show()
  Style:FadeIn(self.frame, 0.38, 0.13, 1)
end

function Options:Toggle()
  if self.frame and self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Open()
  end
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
  if not Options.frame then return end
  if Options.currentPage == "window" and not Options:GetCurrentWindow() then
    Options.selectedWindow = nil
  end
  Shell.RebuildTree(Options)
  if Options.currentPage == "window" and not Options:GetCurrentWindow() then
    Options:OpenPage("general")
  end
end)
