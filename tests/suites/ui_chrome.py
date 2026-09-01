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
      assert(meter.headerRule and meter.headerRule.vertexA == 0.52)
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