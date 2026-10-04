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
      -- The title row draws no strip or rule of its own: the window
      -- backdrop is the only background behind the title and its buttons.
      assert(not rawget(meter, "headerTexture") and not rawget(meter, "headerRule"),
        "the title row must not draw its own background")
      assert(meter.title.textR == 0.76 and meter.title.textG == 0.79 and meter.title.textB == 0.84,
        "meter loaded with settings-selection chrome")

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
      assert(Skada.UI.visualActive == nil,
        "ordinary meter clicks introduced settings-selection chrome")
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
      assert(meter.rows[1].background.alpha == 0.94 * opacity,
        "row back does not follow window opacity")
      meter.db.windowOpacity = 0
      meter.layoutDirty = true
      meter:Refresh()
      assert(meter.frame.skadaBg.alpha == 0,
        "0% window opacity must leave no background")
      meter.db.windowOpacity = 0.9
      meter.layoutDirty = true
      meter:Refresh()
      assert(meter.frame.skadaBg.alpha == 0.9, "window opacity was not restored")
    ''')
    ctx.run('''
      local bordered = {
        visualVersion = 4,
        hideWindowBorder = false,
        windowBorderStyle = "shadow",
        updateRate = 0.1,
        smoothBars = false,
        barSpeed = 1,
        windows = {},
      }
      Skada.WindowConfig.Migrate(bordered)
      assert(bordered.visualVersion == 8 and bordered.windowBorderStyle == "solid",
        "existing bordered profile kept the default grey glow")
      assert(bordered.updateRate == nil and bordered.smoothBars == nil and bordered.barSpeed == nil
        and bordered.hideWindowBorder == nil,
        "obsolete refresh, animation and border flags survived migration")

      local borderless = {
        visualVersion = 4,
        hideWindowBorder = true,
        windowBorderStyle = "shadow",
        windows = {},
      }
      Skada.WindowConfig.Migrate(borderless)
      assert(borderless.visualVersion == 8 and borderless.windowBorderStyle == "none",
        "border migration changed an existing borderless profile")

      -- The profile's mirror of the first window's settings is dropped: each
      -- window owns its settings, and the profile keeps no copy.
      local mirrored = {
        visualVersion = 7, width = 300, mode = "healing", segment = 2, x = 10,
        windows = { { width = 300, mode = "healing", segment = 2, x = 10 } },
      }
      Skada.WindowConfig.Migrate(mirrored)
      assert(mirrored.width == nil and mirrored.mode == nil and mirrored.segment == nil
        and mirrored.x == nil, "the profile kept a copy of the first window's settings")
      assert(mirrored.windows[1].width == 300 and mirrored.windows[1].mode == "healing",
        "dropping the mirror touched the window's own settings")

      -- A fresh profile starts at the current version: no conversions run.
      local fresh = { windows = {} }
      Skada.WindowConfig.Migrate(fresh)
      assert(fresh.visualVersion == 8 and fresh.windowBorderStyle == nil,
        "a fresh profile ran the upgrade conversions")

      -- Docked (bottom-left anchored) windows keep their pixel height across
      -- the trailing-spacing change; free-floating windows keep their rows.
      local docked = {
        visualVersion = 5,
        windows = {
          { point = "BOTTOMLEFT", rows = 10, barHeight = 18, barSpacing = 2 },
          { point = "CENTER", rows = 10, barHeight = 18, barSpacing = 2 },
        },
      }
      Skada.WindowConfig.Migrate(docked)
      local Style = Skada.UIStyle
      assert(math.abs(Style:GetWindowHeight(docked.windows[1], docked.windows[1].rows)
        - (Style.HEADER_HEIGHT + 10 * 20 + Style.FOOTER_HEIGHT)) < 0.01,
        "a docked window changed height on upgrade")
      assert(docked.windows[2].rows == 10, "a floating window's row count was migrated")

      local profile = Skada.db.profile
      local oldStyle = profile.windowBorderStyle
      profile.windowBorderStyle = "shadow"
      Skada.WindowConfig.Migrate(profile)
      assert(profile.windowBorderStyle == "shadow",
        "reload migration overwrote an explicitly selected border style")
      profile.windowBorderStyle = oldStyle
    ''')
    ctx.run('''
      local profile = Skada.db.profile
      local Style = Skada.UIStyle
      local probe = CreateFrame("Frame", nil, UIParent)
      local oldStyle, oldColor, oldClassChrome = profile.windowBorderStyle,
        profile.windowBorderColor, profile.classColorMenus

      profile.classColorMenus = false
      profile.windowBorderColor = { 0.22, 0.44, 0.66 }
      profile.windowBorderStyle = "solid"
      Style:ApplyMeterWindow(probe, false, 0.9)
      local edges = rawget(probe, "skadaBorderEdges")
      assert(edges and edges[1].vertexR == 0.22 and edges[1].vertexG == 0.44 and
        edges[1].vertexB == 0.66 and edges[1]:IsShown(),
        "inactive solid border did not load with its chosen color")
      assert(not rawget(probe, "skadaShadow"), "solid border created a soft shadow")

      profile.windowBorderStyle = "shadow"
      Style:ApplyMeterWindow(probe, true, 0.9)
      assert(edges[1].vertexR == 0.22 and edges[1].vertexG == 0.44 and
        edges[1].vertexB == 0.66,
        "active soft-shadow border replaced its configured color")
      assert(probe.skadaShadow and probe.skadaShadow:IsShown(),
        "soft-shadow border did not show its shadow")

      profile.classColorMenus = true
      local classR, classG, classB = Style:GetAccentColor()
      Style:ApplyMeterWindow(probe, true, 0.9)
      assert(edges[1].vertexR == classR * 0.72 and edges[1].vertexG == classG * 0.72 and
        edges[1].vertexB == classB * 0.72,
        "class-colored chrome did not tint the active soft-shadow edge")

      profile.classColorMenus = false
      profile.windowBorderStyle = "none"
      Style:ApplyMeterWindow(probe, false, 0.9)
      assert(rawget(probe, "backdrop") == nil and not edges[1]:IsShown() and
        not probe.skadaShadow:IsShown(),
        "borderless style left a backdrop edge or shadow visible")

      profile.windowBorderStyle, profile.windowBorderColor = oldStyle, oldColor
      profile.classColorMenus = oldClassChrome
    ''')
    ctx.run('''
      local meter = Skada.UI:GetPrimary()
      local Style = Skada.UIStyle
      local rowStep = meter.db.barHeight + meter.db.barSpacing
      local fullHeight = Style.HEADER_HEIGHT + meter.db.rows * rowStep - meter.db.barSpacing + Style.FOOTER_HEIGHT
      assert(meter.frame.height == fullHeight, "window height does not include the header")
      assert(meter.frame.frameType == "Button" and meter.header:IsShown(),
        "meter background must receive clicks while the title bar is shown")
      assert(not rawget(meter, "clickCatcher"),
        "a hidden-title overlay would block the first meter row")

      meter.db.hideTitle, meter.layoutDirty = true, true
      meter:Refresh()
      local collapsedHeight = Style.HEADLESS_TOP_INSET + meter.db.rows * rowStep - meter.db.barSpacing + Style.FOOTER_HEIGHT
      assert(not meter.header:IsShown(), "hide-title did not hide the header")
      assert(meter.frame.height == collapsedHeight,
        "hide-title did not drop the header from the window height")
      assert(meter.rows[1].lastPointY == -Style.HEADLESS_TOP_INSET,
        "row 1 was not re-anchored just below the window top")
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
        GetHeight = function() return Style.HEADER_HEIGHT + Style.FOOTER_HEIGHT + 10 * 11 - 1 end,
      }
      local resizeWindow = {
        frame = resizeFrame,
        db = { barHeight = 10, barSpacing = 1 },
        manager = { NotifyWindowChanged = function() end },
      }
      Skada.UISnapDock.PersistGeometry(resizeWindow, false)
      assert(resizeWindow.db.rows == 10, "unchanged window height gained a meter row")
    ''')
    ctx.run('''
      -- PersistGeometry must preserve an off-grid height exactly (snapSize
      -- copies the neighbour's raw pixel height) so a later ApplyLayout
      -- reproduces it instead of popping the window to a new size or
      -- unaligning a snapped edge; the fractional remainder paints as a
      -- short trailing bar rather than an empty band.
      local Style = Skada.UIStyle
      local gridFrame = {
        GetWidth = function() return 240 end,
        GetHeight = function() return 219.5 end,
        SetHeight = function(self, value) self.height = value end,
      }
      local gridWindow = {
        frame = gridFrame,
        db = { barHeight = 18, barSpacing = 2, hideTitle = true },
        manager = { NotifyWindowChanged = function() end },
      }
      Skada.UISnapDock.PersistGeometry(gridWindow, false)
      local expectedHeight = Style.HEADLESS_TOP_INSET
        + gridWindow.db.rows * (gridWindow.db.barHeight + gridWindow.db.barSpacing)
        - gridWindow.db.barSpacing + Style.FOOTER_HEIGHT
      assert(math.abs(expectedHeight - 219.5) < 0.01,
        "persisted rows no longer reproduce the copied height: " ..
        tostring(expectedHeight) .. " vs 219.5")
      assert(gridWindow.db.rows ~= math.floor(gridWindow.db.rows),
        "off-grid height was rounded down to whole rows")
      assert(gridWindow.layoutDirty, "PersistGeometry did not mark the layout dirty")
    ''')
    ctx.run('''
      -- A frame whose GetPoint comes back empty (the vanilla client after
      -- an engine rebuild of the anchors during a drag) must not nil the
      -- window's stored geometry: the next ApplyLayout would anchor with
      -- nils and throw the SetPoint usage error on every rebuild after.
      local Style = Skada.UIStyle
      local savedGeometry = { rows = 10, barHeight = 18, barSpacing = 2, hideTitle = true }
      local draggedFrame = {
        GetWidth = function() return 240 end,
        GetHeight = function() return Style:GetWindowHeight(savedGeometry, 10) end,
        SetHeight = function() end,
        GetPoint = function() return nil end,
      }
      local draggedWindow = {
        frame = draggedFrame,
        db = { barHeight = 18, barSpacing = 2, hideTitle = true,
          point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -10 },
        manager = { NotifyWindowChanged = function() end },
      }
      Skada.UISnapDock.PersistGeometry(draggedWindow, true)
      assert(draggedWindow.db.point == "TOPLEFT"
        and draggedWindow.db.relativePoint == "TOPLEFT"
        and draggedWindow.db.x == 10 and draggedWindow.db.y == -10,
        "an anchor-less GetPoint read wiped the stored geometry")

      -- A frame with no stored anchor either (a window whose layout never
      -- ran when the read happened) falls back to a legal anchor instead.
      local bareWindow = {
        frame = { GetWidth = function() return 240 end,
          GetHeight = function() return 300 end, SetHeight = function() end,
          GetPoint = function() return nil end },
        db = { barHeight = 18, barSpacing = 2 },
        manager = { NotifyWindowChanged = function() end },
      }
      Skada.UISnapDock.PersistGeometry(bareWindow, true)
      assert(bareWindow.db.point == "CENTER"
        and bareWindow.db.relativePoint == "CENTER"
        and bareWindow.db.x == 0 and bareWindow.db.y == 0,
        "a first anchor-less GetPoint read left no legal anchor behind")
    ''')
    ctx.run('''
      -- ApplyLayout itself must never hand the engine a nil or non-string
      -- anchor: corrupt or half-missing saved geometry is repaired in the
      -- window's settings instead of throwing the SetPoint usage error.
      local meter = Skada.UI:GetPrimary()
      local saved = {
        point = meter.db.point, relativePoint = meter.db.relativePoint,
        x = meter.db.x, y = meter.db.y,
      }
      meter.db.point, meter.db.relativePoint, meter.db.x, meter.db.y = nil, nil, "bad", -0.5
      meter.layoutDirty = true
      meter:ApplyLayout()
      assert(meter.db.point == "CENTER" and meter.db.relativePoint == "CENTER"
        and meter.db.x == 0 and meter.db.y == -0.5,
        "ApplyLayout did not repair the corrupt geometry in place")
      meter.db.point, meter.db.relativePoint, meter.db.x, meter.db.y
        = saved.point, saved.relativePoint, saved.x, saved.y
      meter.layoutDirty = true
      meter:ApplyLayout()
    ''')
    ctx.run('''
      -- A fractional row count (a snap-copied off-grid height) must fill the
      -- window to its bottom edge: the whole rows paint at full height and
      -- the remainder paints as a short trailing bar instead of leaving an
      -- empty band under the last bar.
      local meter = Skada.UI:GetPrimary()
      local Style = Skada.UIStyle
      local savedRows = meter.db.rows
      local rowStep = meter.db.barHeight + meter.db.barSpacing
      meter.db.rows = 6.4
      meter.layoutDirty = true
      meter:Refresh()
      assert(meter.frame.height == Style.HEADER_HEIGHT + meter.db.rows * rowStep - meter.db.barSpacing + Style.FOOTER_HEIGHT,
        "frame did not keep the snap-copied fractional height")
      assert(meter.rows[6].height == meter.db.barHeight, "row 6 is not a full bar")
      assert(meter.rows[7].height == (meter.db.rows - 6) * rowStep - meter.db.barSpacing,
        "the fractional row remainder did not paint as a trailing bar")
      meter.db.rows, meter.layoutDirty = savedRows, true
      meter:Refresh()
    ''')
    ctx.run('''
      -- A remainder that is mathematically 6px must still paint as a trailing
      -- bar: float rounding through contentHeight / rowStep can land just
      -- below the 6px threshold.
      local meter = Skada.UI:GetPrimary()
      local savedRows = meter.db.rows
      meter.db.rows = 16.4
      meter.layoutDirty = true
      meter:Refresh()
      assert(meter.rows[17].height > 5.9,
        "an exactly-6px trailing bar was dropped to float rounding: " ..
        tostring(meter.rows[17].height))
      meter.db.rows, meter.layoutDirty = savedRows, true
      meter:Refresh()
    ''')
    ctx.run('''
      -- A window whose build failed mid-InitializeWindow stays registered for
      -- the settings list but is inert: refreshes must skip it entirely
      -- instead of erroring on whatever the failed build left nil.
      local meter = Skada.UI:GetPrimary()
      local titleBefore = meter.title.textValue
      meter.broken = true
      Skada.UI:RefreshAll()
      meter:Animate()
      assert(meter.title.textValue == titleBefore, "a broken window kept refreshing")
      meter.broken = nil
      meter:Refresh()
    ''')
    ctx.run('''
      -- The minimap show/hide-all toggle ignores a broken window's stale
      -- `visible` flag: counting it would make every click a "hide" and the
      -- working windows could never be shown again.
      local meter = Skada.UI:GetPrimary()
      local savedVisible = meter.db.visible
      local brokenWindow = { broken = true, db = { visible = true } }
      table.insert(Skada.UI.windows, brokenWindow)
      meter.db.visible = true
      assert(Skada.UI:ToggleAllWindows() == false, "toggle with a shown window must hide")
      assert(meter.db.visible == false, "the working window was not hidden")
      assert(Skada.UI:ToggleAllWindows() == true,
        "a broken window's stale visible flag blocked show-all")
      assert(meter.db.visible == true, "the working window was not shown again")
      assert(brokenWindow.db.visible == true, "a broken window's flag must be left alone")
      table.remove(Skada.UI.windows)

      -- Show-all brings back only what hide-all hid: a window the player
      -- hid on purpose stays hidden.
      local hiddenOnPurpose = { db = { visible = true } }
      table.insert(Skada.UI.windows, hiddenOnPurpose)
      Skada.UI:SetWindowVisible(hiddenOnPurpose, false)
      assert(Skada.UI:ToggleAllWindows() == false)
      assert(meter.db.visible == false and meter.db.hiddenByToggle == true)
      assert(hiddenOnPurpose.db.hiddenByToggle == nil, "an already-hidden window was marked")
      assert(Skada.UI:ToggleAllWindows() == true)
      assert(meter.db.visible == true and meter.db.hiddenByToggle == nil,
        "show-all did not bring back the window it hid")
      assert(hiddenOnPurpose.db.visible == false, "show-all revealed a window hidden on purpose")
      -- With nothing marked (every window hidden one by one), show-all shows all.
      Skada.UI:SetWindowVisible(meter, false)
      assert(Skada.UI:ToggleAllWindows() == true)
      assert(meter.db.visible == true and hiddenOnPurpose.db.visible == true,
        "show-all with nothing marked must show every window")
      table.remove(Skada.UI.windows)
      meter.db.visible = savedVisible
      if savedVisible then meter.frame:Show() else meter.frame:Hide() end
      meter.layoutDirty = true
      meter:Refresh()
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
      local Style = Skada.UIStyle
      assert(popup.width == 380 and popup.height == 185)
      assert(popup.backdrop == Style.DIALOG_BACKDROP and
        popup.backdropR == 1 and popup.backdropA == 1)
      assert(popup.dialogTitle.textValue == "Skada" and
        popup.dialogTitle.textR == Style.GOLD_R and
        popup.dialogTitle.fontPath == Style.UI_FONT)
      assert(popup.pane.backdrop == Style.PANE_BACKDROP and
        popup.pane.backdropA == Style.PANE_BG_A and
        popup.pane.borderR == Style.PANE_BORDER_R)
      assert(popup.targetPane.backdrop == Style.PANE_BACKDROP and
        popup.targetPane.backdropA == 1)
      assert(popup.title ~= nil and
        popup.subtitle.textValue == "Send the current view to a chat channel.")
      assert(table.getn(popup.channelButtons) == 4 and
        popup.channelButtons[1].textValue == "Guild" and
        popup.channelButtons[2].textValue == "Party/Raid" and
        popup.channelButtons[3].textValue == "Say" and
        popup.channelButtons[4].textValue == "Whisper")
      assert(popup.whisper.fontPath == Style.UI_FONT and
        popup.close.textValue == (CLOSE or "Close"))
      assert(popup.alpha == 0.38 and rawget(popup, "OnUpdate"))
      popup.OnUpdate(popup, 0.13)
      assert(popup.alpha == 1 and not rawget(popup, "OnUpdate"))
      popup:Hide()
    ''')
    assert ctx.skada.UI.NeedsContinuousRefresh(ctx.skada.UI) is False
    for ui_file in ("ui/ui.lua", "ui/ui.presenter.lua", "ui/ui.config.lua"):
        assert "SetWordWrap" not in (ROOT / ui_file).read_text(encoding="utf-8"), ui_file
