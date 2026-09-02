"""Suite: ui_chrome - header buttons, action menu, snap dock, report popup."""

from harness import Context, ROOT


def run(ctx: Context):
    ctx.run(r'''
      local meter = Skada.UI:GetPrimary()
      local Style = Skada.UIStyle
      local expected = {
        "Interface\\Icons\\INV_Misc_Gear_01",
        false,
        "Interface\\Icons\\Spell_Nature_Lightning",
      }
      assert(table.getn(meter.headerButtons) == table.getn(expected))
      local i, button
      for i = 1, table.getn(expected) do
        button = meter.headerButtons[i]
        if expected[i] then
          assert(button.icon and button.icon.texture == expected[i],
            "header button " .. i .. " is missing its icon")
        elseif i == 2 then
          assert(not button.icon:IsShown() and button.text and
            button.text.textValue == "A" and button.text.fontSize == 12 and
            button.text.skadaOffsetX == 2 and button.text.skadaOffsetY == 0,
            "automatic segments was not rendered as A")
        end
        assert(button.width == Style.HEADER_BUTTON_WIDTH and
          button.height == Style.HEADER_BUTTON_HEIGHT)
        assert(button.width == button.height, "header control is not square")
        assert(button.hitLeft == -1 and button.hitRight == -1 and
          button.hitTop == -1 and button.hitBottom == -1)
        assert(button.alpha == Style.HEADER_BUTTON_ALPHA)
      end
      assert(meter.headerButtons[1] == meter.menuButton)
      assert(meter.headerButtons[2] == meter.autoButton)
      assert(meter.headerButtons[3] == meter.modeButton)
      assert(not rawget(meter, "segmentButton"))
      assert(not rawget(meter, "settingsButton"))
      assert(not rawget(meter, "logButton"))
      assert(not rawget(meter, "reportButton"))
      assert(not rawget(meter, "resetButton"))
      assert(not rawget(meter, "newButton"))
      assert(not rawget(meter, "removeButton"))
      assert(meter.db.width >= Style.MIN_WINDOW_WIDTH)
      assert(meter.autoButton.skadaActive and not rawget(meter.autoButton, "activeMarker"))
      assert(meter.autoButton.text.textR == 0.2 and meter.autoButton.text.textG == 1 and
        meter.autoButton.text.textB == 0.2)
      assert(meter.headerRule and
        meter.headerRule.alpha == 0.52 * meter.db.windowOpacity,
        "active header rule must fade with window opacity")
      assert(meter.title.textR == 0.94 and meter.title.textG == 0.95 and meter.title.textB == 0.98)

      local menu = meter.actionMenu
      assert(menu and not menu:IsShown())
      assert(table.getn(menu.entries) == 6)
      assert(menu.byKey.settings.text.textValue == "Settings")
      assert(menu.byKey.logging.text.textValue == "Combat logging")
      assert(menu.byKey.report.text.textValue == "Report meter")
      assert(menu.byKey.new.text.textValue == "+  New window")
      assert(menu.byKey.remove.text.textValue == "-  Remove window")
      assert(menu.byKey.reset.text.textValue == "Reset all fight data")
      assert(menu.byKey.reset.text.textR == 1 and menu.byKey.reset.text.textG == 0.48)
      menu:Toggle()
      assert(menu:IsShown() and not menu.byKey.remove:IsShown())
      assert(menu.height == 128 and menu.byKey.logging.value.textValue == "Off")
      assert(menu.lastPoint == "TOPRIGHT" and menu.lastRelativeTo == meter.menuButton)
      assert(menu.alpha == 0.45 and rawget(menu, "OnUpdate"))
      menu.byKey.settings.OnEnter(menu.byKey.settings)
      assert(menu.byKey.settings.marker:IsShown() and menu.byKey.settings.marker.vertexR == 0.38)
      menu.byKey.settings.OnLeave(menu.byKey.settings)
      assert(not menu.byKey.settings.marker:IsShown())
      menu.OnUpdate(menu, 0.10)
      assert(menu.alpha == 1 and not rawget(menu, "OnUpdate"))
      menu:Hide()

      -- Header controls keep their left-click action, but right-click means
      -- back everywhere inside the window.
      local autoBefore = meter.db.autoSwitch
      local i
      for i = 1, table.getn(meter.headerButtons) do
        meter:SetView("mode")
        meter.headerButtons[i].OnClick(meter.headerButtons[i], "RightButton")
        assert(meter.view == "modes" and not menu:IsShown(),
          "header control " .. i .. " did not navigate back")
      end
      assert(meter.db.autoSwitch == autoBefore,
        "right-clicking the automatic-segment control toggled it")
      meter:SetView("mode")

      assert(meter.header.height == Style.HEADER_BUTTON_HEIGHT)
      assert(meter.title.lastPoint == "RIGHT" and meter.title.lastRelativeTo == meter.modeButton)
      local defaultWidth, defaultHeight = meter.db.width, meter.frame.height
      meter.db.width, meter.layoutDirty = Style.MIN_WINDOW_WIDTH, true
      meter:Refresh()
      assert(meter.header.height == Style.HEADER_BUTTON_HEIGHT)
      assert(meter.frame.height == defaultHeight)
      assert(meter.title.lastPoint == "RIGHT" and meter.title.lastRelativeTo == meter.modeButton)
      meter.db.width, meter.layoutDirty = defaultWidth, true
      meter:Refresh()
    ''')
    ctx.run('''
      -- window opacity is per window and must reach every visible chrome
      -- layer through SetAlpha (backdrop-color alpha is not honored on all
      -- clients)
      local meter = Skada.UI:GetPrimary()
      local opacity = meter.db.windowOpacity
      assert(meter.frame.skadaBg and meter.frame.skadaBg.alpha == opacity,
        "window fill does not follow window opacity")
      assert(meter.headerTexture.alpha == 0.92 * opacity,
        "header texture does not follow window opacity")
      assert(meter.rows[1].background.alpha == 0.94 * opacity,
        "row back does not follow window opacity")
      meter.db.windowOpacity = 0
      meter.layoutDirty = true
      meter:Refresh()
      assert(meter.frame.skadaBg.alpha == 0 and meter.headerTexture.alpha == 0,
        "0% window opacity must leave no background")
      meter.db.windowOpacity = 0.9
      meter.layoutDirty = true
      meter:Refresh()
      assert(meter.frame.skadaBg.alpha == 0.9, "window opacity was not restored")
    ''')
    ctx.run('''
      local profile = Skada.db.profile
      local Style = Skada.UIStyle
      local probe = CreateFrame("Frame", nil, UIParent)
      local oldStyle, oldColor, oldHidden = profile.windowBorderStyle,
        profile.windowBorderColor, profile.hideWindowBorder

      profile.hideWindowBorder = false
      profile.windowBorderColor = { 0.22, 0.44, 0.66 }
      profile.windowBorderStyle = "solid"
      Style:ApplyMeterWindow(probe, true, 0.9)
      assert(probe.borderR == 0.22 and probe.borderG == 0.44 and probe.borderB == 0.66,
        "solid border did not keep its chosen color while active")
      assert(not rawget(probe, "skadaShadow"), "solid border created a soft shadow")

      profile.windowBorderStyle = "shadow"
      Style:ApplyMeterWindow(probe, false, 0.9)
      assert(probe.skadaShadow and probe.skadaShadow:IsShown(),
        "soft-shadow border did not show its shadow")

      profile.windowBorderStyle = "none"
      Style:ApplyMeterWindow(probe, false, 0.9)
      assert(probe.borderA == 0 and not probe.skadaShadow:IsShown(),
        "borderless style left an edge or shadow visible")

      profile.windowBorderStyle, profile.windowBorderColor = oldStyle, oldColor
      profile.hideWindowBorder = oldHidden
    ''')
    ctx.run('''
      local meter = Skada.UI:GetPrimary()
      local Style = Skada.UIStyle
      local rowStep = meter.db.barHeight + meter.db.barSpacing
      local fullHeight = Style.HEADER_HEIGHT + meter.db.rows * rowStep + Style.FOOTER_HEIGHT
      assert(meter.frame.height == fullHeight, "window height does not include the header")
      assert(meter.frame.frameType == "Button" and meter.header:IsShown(),
        "meter background must receive clicks while the title bar is shown")
      assert(not rawget(meter, "clickCatcher"),
        "a hidden-title overlay would block the first meter row")

      meter.db.hideTitle, meter.layoutDirty = true, true
      meter:Refresh()
      local collapsedHeight = meter.db.rows * rowStep + Style.FOOTER_HEIGHT
      assert(not meter.header:IsShown(), "hide-title did not hide the header")
      assert(meter.frame.height == collapsedHeight,
        "hide-title did not drop the header from the window height")
      assert(meter.rows[1].lastPointY == 0, "row 1 was not re-anchored to the window top")
      -- Hidden title bars expose no menu or automatic-segment control, while
      -- the window background still handles navigation on an empty meter.
      local menu = meter.actionMenu
      meter.view, meter.detailActor = "mode", nil
      assert(not menu:IsShown())
      meter.frame.OnClick(meter.frame, "RightButton")
      assert(meter.view == "modes" and not menu:IsShown(),
        "hidden-title background right-click did not navigate back")
      meter.frame.OnClick(meter.frame, "RightButton")
      assert(meter.view == "segments" and not menu:IsShown(),
        "empty window-space right-click did not navigate back")
      meter:SetView("mode")

      meter.db.hideTitle, meter.layoutDirty = false, true
      meter:Refresh()
      assert(meter.header:IsShown())
      assert(meter.frame.height == fullHeight, "window height was not restored with the header")
      assert(meter.rows[1].lastPointY == -Style.HEADER_HEIGHT,
        "row 1 was not re-anchored below the restored header")
    ''')
    ctx.run('''
      local meter = Skada.UI:GetPrimary()
      local row = meter.rows[1]
      meter.view, meter.detailActor = "mode", nil

      -- dragging from a row moves the window instead of drilling into details
      row.OnMouseDown(row)
      assert(not meter.windowWasDragged)
      row.OnDragStart(row)
      assert(meter.windowWasDragged, "row drag start did not mark the window as dragged")
      row.OnClick(row, "LeftButton")
      assert(not meter.windowWasDragged and meter.detailActor == nil,
        "row click after a drag must not open the detail view")

      -- a plain row click still drills down
      row.entry = { actor = { name = "DragProbe" } }
      row.OnClick(row, "LeftButton")
      assert(meter.detailActor == "DragProbe", "plain row click lost its drill-down")
      meter.detailActor, row.entry = nil, nil

      -- dragging from the window background moves the window as well
      meter.frame.OnDragStart(meter.frame)
      assert(meter.headerWasDragged, "frame drag start did not mark the window as dragged")
      meter.headerWasDragged = nil
    ''')
    ctx.run('''
      local frame = {
        GetLeft = function() return 400 end,
        GetBottom = function() return 4 end,
        GetWidth = function() return 240 end,
        GetHeight = function() return 200 end,
        GetEffectiveScale = function() return 0.5 end,
        ClearAllPoints = function() end,
        SetPoint = function(self, point, _, relativePoint, x, y)
          self.point, self.relativePoint, self.x, self.y = point, relativePoint, x, y
        end,
      }
      local window = {
        frame = frame,
        db = { snap = true, snapDistance = 12, snapGap = 0, snapSize = false },
      }
      UIParent.width, UIParent.height = 1920, 1080
      UIParent.GetScale = function() return 0.5 end
      Skada.UISnapDock.SnapWindow({ windows = { window } }, window)
      assert(frame.point == "BOTTOMLEFT" and frame.relativePoint == "BOTTOMLEFT")
      assert(frame.x == 400 and frame.y == 0,
        "bottom-edge snap changed the window's horizontal position")
      assert(window.db.x == 400 and window.db.y == 0,
        "bottom-edge snap persisted scaled screen coordinates")
      UIParent.width, UIParent.height, UIParent.GetScale = nil, nil, nil
    ''')
    ctx.run('''
      local Style = Skada.UIStyle
      local resizeFrame = {
        GetWidth = function() return 240 end,
        GetHeight = function() return Style.HEADER_HEIGHT + Style.FOOTER_HEIGHT + 10 * 11 end,
      }
      local resizeWindow = {
        frame = resizeFrame,
        db = { barHeight = 10, barSpacing = 1 },
        manager = { SyncLegacy = function() end },
      }
      Skada.UISnapDock.PersistGeometry(resizeWindow, false)
      assert(resizeWindow.db.rows == 10, "unchanged window height gained a meter row")
    ''')
    ctx.run('''
      -- PersistGeometry must preserve an off-grid height exactly (snapSize
      -- copies the neighbour's raw pixel height) so a later ApplyLayout
      -- reproduces it instead of popping the window to a new size.
      local Style = Skada.UIStyle
      local gridFrame = {
        GetWidth = function() return 240 end,
        GetHeight = function() return 219.5 end,
        SetHeight = function(self, value) self.height = value end,
      }
      local gridWindow = {
        frame = gridFrame,
        db = { barHeight = 18, barSpacing = 2, hideTitle = true },
        manager = { SyncLegacy = function() end },
      }
      Skada.UISnapDock.PersistGeometry(gridWindow, false)
      local expectedHeight = gridWindow.db.rows * (gridWindow.db.barHeight + gridWindow.db.barSpacing)
        + Style.FOOTER_HEIGHT
      assert(math.abs(expectedHeight - 219.5) < 0.01,
        "persisted rows no longer reproduce the copied height: " ..
        tostring(expectedHeight) .. " vs 219.5")
      assert(gridWindow.db.rows ~= math.floor(gridWindow.db.rows),
        "off-grid height was rounded down to whole rows")
      assert(gridWindow.layoutDirty, "PersistGeometry did not mark the layout dirty")
    ''')
    ctx.run('''
      -- Side-by-side dock: adopt the target's height, keep the width.
      local function fakeFrame(l, b, w, h)
        local f = {}
        f.left, f.bottom, f.width, f.height = l, b, w, h
        f.GetLeft = function() return f.left end
        f.GetBottom = function() return f.bottom end
        f.GetWidth = function() return f.width end
        f.GetHeight = function() return f.height end
        f.GetEffectiveScale = function() return 1 end
        f.ClearAllPoints = function() end
        f.SetWidth = function(self, value) f.width = value end
        f.SetHeight = function(self, value) f.height = value end
        f.SetPoint = function(self, point, _, relativePoint, x, y)
          f.point, f.relativePoint, f.left, f.bottom = point, relativePoint, x, y
        end
        return f
      end
      local parentFrame = fakeFrame(100, 200, 240, 234)
      local parent = { frame = parentFrame, db = { visible = true } }
      local frame = fakeFrame(344, 208, 200, 106)
      local window = {
        frame = frame,
        db = { snap = true, snapDistance = 12, snapGap = 0, snapSize = true },
      }
      UIParent.width, UIParent.height = 1920, 1080
      Skada.UISnapDock.SnapWindow({ windows = { parent, window } }, window)
      assert(frame.width == 200 and frame.height == parentFrame.height,
        "side-by-side snap did not adopt the target's height only")
      assert(frame.left == parentFrame.left + parentFrame.width,
        "nearest-target snap did not land against the target frame")
      UIParent.width, UIParent.height = nil, nil
    ''')
    ctx.run('''
      -- Stacked dock: adopt the target's width, keep the row count.
      local function fakeFrame(l, b, w, h)
        local f = {}
        f.left, f.bottom, f.width, f.height = l, b, w, h
        f.GetLeft = function() return f.left end
        f.GetBottom = function() return f.bottom end
        f.GetWidth = function() return f.width end
        f.GetHeight = function() return f.height end
        f.GetEffectiveScale = function() return 1 end
        f.ClearAllPoints = function() end
        f.SetWidth = function(self, value) f.width = value end
        f.SetHeight = function(self, value) f.height = value end
        f.SetPoint = function(self, point, _, relativePoint, x, y)
          f.point, f.relativePoint, f.left, f.bottom = point, relativePoint, x, y
        end
        return f
      end
      local parentFrame = fakeFrame(100, 200, 240, 234)
      local parent = { frame = parentFrame, db = { visible = true } }
      local frame = fakeFrame(110, 442, 220, 106)
      local window = {
        frame = frame,
        db = { snap = true, snapDistance = 12, snapGap = 0, snapSize = true },
      }
      UIParent.width, UIParent.height = 1920, 1080
      Skada.UISnapDock.SnapWindow({ windows = { parent, window } }, window)
      assert(frame.width == parentFrame.width and frame.height == 106,
        "stacked snap did not adopt the target's width only")
      assert(frame.bottom == parentFrame.bottom + parentFrame.height,
        "stacked snap did not land against the target frame")
      UIParent.width, UIParent.height = nil, nil
    ''')
    ctx.run('''
      Skada.UI:ShowReportPopup(Skada.UI:GetPrimary())
      local popup = Skada.UI.reportPopup
      assert(popup.title ~= nil and popup.subtitle.textValue == "Send the current view")
      assert(popup.alpha == 0.42 and rawget(popup, "OnUpdate"))
      popup.OnUpdate(popup, 0.11)
      assert(popup.alpha == 1 and not rawget(popup, "OnUpdate"))
      popup:Hide()
    ''')
    assert ctx.skada.UI.NeedsContinuousRefresh(ctx.skada.UI) is False
    for ui_file in ("ui/ui.lua", "ui/ui.presenter.lua", "ui/ui.config.lua"):
        assert "SetWordWrap" not in (ROOT / ui_file).read_text(encoding="utf-8"), ui_file
