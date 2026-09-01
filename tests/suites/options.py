"""Suite: options - profile defaults, settings panel, reset policies, minimap."""

from harness import Context


def run(ctx: Context):
    skada = ctx.skada
    assert skada.db.profile.classColors is True
    assert skada.db.profile.fontName == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf"
    assert skada.db.profile.minimap.show is True
    assert skada.Options.minimapButton is not None

    ctx.run(r'''
      Skada.Options:Open()
      assert(Skada.Options.frame and Skada.Options.frame:IsShown())
      assert(Skada.Options.title.textValue == "Skada")
      assert(Skada.Options.statusText.textValue == "Core behavior and everyday conveniences.")
      assert(Skada.Options.frame.backdropR == 0 and Skada.Options.frame.backdropA == 1)
      assert(Skada.Options.viewport.backdropA == 0.5 and Skada.Options.viewport.borderR == 0.4)
      assert(Skada.Options.treePanel.backdropA == 0.5 and Skada.Options.treePanel.borderR == 0.4)
      assert(Skada.Options.title.textR == 1 and Skada.Options.title.textG == 0.82)
      assert(Skada.Options.scrollbar.width == 10)
      assert(Skada.Options.scrollbar.track.width == 6 and Skada.Options.scrollbar.thumb.width == 6)
      assert(not rawget(Skada.Options.scrollbar, "up") and not rawget(Skada.Options.scrollbar, "down"))
      Skada.Options:OpenPage("window")
      local windowSpec = Skada.OptionsSchema.pages.window.rows
      assert(windowSpec and table.getn(windowSpec) == 40, "window page must hold every row")
      assert(windowSpec[1].key == "combatHeader" and windowSpec[1].widget == "header")
      Skada.Options:OpenPage("general")
      local capturedScroll = -1
      local modernScroll = Skada.Options.kit.createScrollbar(Skada.Options.frame,
        Skada.Options.viewport, function(offset) capturedScroll = offset end)
      modernScroll.track.height, modernScroll.track.top = 400, 400
      modernScroll:SetRange(800, 400)
      modernScroll:Update(0)
      assert(modernScroll.thumb.height == 200)
      GetCursorPosition = function() return 0, 300 end
      modernScroll.track.OnClick()
      assert(capturedScroll == 100, capturedScroll)
      modernScroll.thumb.top = 400
      GetCursorPosition = function() return 0, 350 end
      modernScroll.thumb.OnMouseDown()
      assert(rawget(modernScroll, "OnUpdate"))
      GetCursorPosition = function() return 0, 250 end
      modernScroll.OnUpdate()
      assert(capturedScroll == 200, capturedScroll)
      modernScroll.thumb.OnMouseUp()
      assert(not rawget(modernScroll, "OnUpdate"))
      GetCursorPosition = nil
      assert(Skada.Options.frame.alpha == 0.38 and rawget(Skada.Options.frame, "OnUpdate"))
      Skada.Options.frame.OnUpdate(Skada.Options.frame, 0.13)
      assert(Skada.Options.frame.alpha == 1 and not rawget(Skada.Options.frame, "OnUpdate"))
      local primary = Skada.UI:GetPrimary()
      assert(Skada.Options.selectedWindow == primary)

      -- closing the settings must drop the selection border from the meters
      Skada.Options:SelectWindow(primary)
      local borderWhileSelected = primary.frame.borderR
      Skada.Options.frame.OnHide()
      assert(Skada.UI.visualActive == nil, "settings close kept the visual selection")
      assert(primary.frame.borderR == 0.10 and primary.frame.borderR ~= borderWhileSelected,
        "settings close did not drop the selection border")
      Skada.Options:SelectWindow(primary)
      assert(primary.frame.borderR == borderWhileSelected,
        "reselecting did not restore the selection border")
      Skada.Options:OpenPage("general")

      assert(Skada.Options.currentPage == "general")
      local generalPage = Skada.Options.pageCache.general
      assert(generalPage.description.textValue == "Core behavior and everyday conveniences.")
      assert(generalPage.description:IsShown() and generalPage.rule:IsShown())
      assert(generalPage.content.alpha == 0.48 and rawget(generalPage.content, "OnUpdate"))
      generalPage.content.OnUpdate(generalPage.content, 0.11)
      assert(generalPage.content.alpha == 1 and not rawget(generalPage.content, "OnUpdate"))
      Skada.Options:OpenPage("data")
      assert(Skada.Options.currentPage == "data")
      assert(not generalPage.description:IsShown() and not generalPage.rule:IsShown())
      Skada.Options:OpenPage("window")
      assert(Skada.Options.currentPage == "window")
      Skada.Options:OpenPage("general")

      local i, control
      for i = 1, table.getn(Skada.Options.controls) do
        control = Skada.Options.controls[i]
        assert(control.width and control.width > 0,
          "settings control " .. i .. " has no width")
      end
      for i = 1, table.getn(Skada.Options.treeRows) do
        control = Skada.Options.treeRows[i]
        assert(control.width and control.width > 0,
          "tree node row " .. i .. " has no width")
      end

      local second = Skada.UI:CreateNew("Settings meter")
      Skada.Options:CycleWindow(1)
      assert(Skada.Options.selectedWindow == second)
      assert(Skada.UI:GetActive() == second)
      Skada.Options:CycleWindow(1)
      assert(Skada.Options.selectedWindow == primary)
      Skada.Options:CycleWindow(-1)
      assert(Skada.Options.selectedWindow == second)

      second.db.width = 321
      Skada.Options.frame:Hide()
      Skada.Options:Open()
      assert(Skada.Options.selectedWindow == second and second.db.width == 321)

      Skada.db.profile.fontName = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf"
      local fontRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "key") == "fontName" then fontRow = row break end
      end
      assert(fontRow, "bar font dropdown row not found")
      fontRow.chrome.OnClick()
      assert(fontRow.menuFrame, "font dropdown menu frame was not created")
      local function pickFont(value)
        TestDropdownInfos = {}
        fontRow.menuFrame.initialize(fontRow.menuFrame, 1)
        local j, info
        for j = 1, table.getn(TestDropdownInfos) do
          info = TestDropdownInfos[j]
          if info.value == value then info.func() return end
        end
        error("font dropdown is missing a choice: " .. value)
      end
      pickFont("Fonts\\FRIZQT__.TTF")
      assert(Skada.db.profile.fontName == "Fonts\\FRIZQT__.TTF")
      pickFont("Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")
      assert(Skada.db.profile.fontName == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")

      local checkRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "setValue") and rawget(row, "label") == "Merge pets into owners" then checkRow = row break end
      end
      assert(checkRow, "merge pets checkbox row not found")
      local before = Skada.db.profile.mergePets
      local flipped = not before
      checkRow.setValue(flipped)
      assert(Skada.db.profile.mergePets == flipped)
      checkRow.setValue(before)

      local sliderRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "label") == "Font size" then sliderRow = row break end
      end
      assert(sliderRow, "font size slider row not found")
      local target = Skada.Options.selectedWindow
      GetCursorPosition = function() return 500, 300 end
      sliderRow.track.left = 2
      sliderRow.OnMouseDown()
      assert(target.db.fontSize == 22, target.db.fontSize)
      GetCursorPosition = function() return 200, 300 end
      sliderRow.OnMouseDown()
      assert(target.db.fontSize == 15, target.db.fontSize)
      sliderRow.OnMouseUp()

      -- a drag keeps following the cursor after it leaves the thin track
      local savedIsDown = IsMouseButtonDown
      IsMouseButtonDown = function() return true end
      sliderRow.OnMouseDown()
      GetCursorPosition = function() return 500, 300 end
      sliderRow.OnUpdate()
      assert(target.db.fontSize == 22, target.db.fontSize)
      GetCursorPosition = function() return 40, 300 end
      sliderRow.OnUpdate()
      assert(target.db.fontSize < 15 and target.db.fontSize >= 8,
        "dragging off the track stopped updating the slider: " .. tostring(target.db.fontSize))
      IsMouseButtonDown = function() return false end
      sliderRow.OnUpdate()
      IsMouseButtonDown = savedIsDown

      local widthRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "label") == "Width" then widthRow = row break end
      end
      assert(widthRow, "width slider row not found")
      local profileWidthBefore = Skada.db.profile.width
      GetCursorPosition = function() return 205, 300 end
      widthRow.track.left = 2
      widthRow.OnMouseDown()
      widthRow.OnMouseUp()
      assert(Skada.Options.selectedWindow == second)
      assert(second.db.width ~= 321 and second.db.width >= Skada.UIStyle.MIN_WINDOW_WIDTH and second.db.width <= 600,
        second.db.width)
      assert(Skada.db.profile.width == profileWidthBefore,
        "secondary window design key leaked into the profile mirror")
      Skada.UI:SetActive(primary)
      Skada.Options:SelectWindow(primary)
      assert(Skada.Options.selectedWindow == primary)
      GetCursorPosition = function() return 500, 300 end
      widthRow.OnMouseDown()
      widthRow.OnMouseUp()
      assert(Skada.db.profile.width == primary.db.width,
        "primary window design key was not mirrored into the profile")

      Skada.Options:OpenPage("window")
      local winPage = Skada.Options.pageCache.window
      assert(winPage and not winPage.strip, "window page must be a single scrollable page")
      local rowForKey = {}
      local i
      for i = 1, table.getn(winPage.rows) do
        local row = winPage.rows[i]
        if row.key then rowForKey[row.key] = row end
      end
      assert(rowForKey.width and rowForKey.name and rowForKey.mode and rowForKey.segment
        and rowForKey.combatMode and rowForKey.returnAfterCombat
        and rowForKey.deleteWindow, "window page rows missing")
      -- the page leads with combat switching, readable without any scrolling
      assert(rowForKey.combatHeader:IsShown() and rowForKey.designHeader:IsShown(),
        "section headers must render")
      assert(rowForKey.combatMode:IsShown() and rowForKey.returnAfterCombat:IsShown(),
        "combat rows must be visible without scrolling")
      -- the remaining sections live further down the single page
      assert(not rowForKey.mode:IsShown(), "mode rows must sit below the fold until scrolled")
      -- no row may render up in the page header band: a shown row's top edge
      -- must stay at or below the content area's top (headerPad down the pane)
      local i, row
      for i = 1, table.getn(winPage.rows) do
        row = winPage.rows[i]
        assert(not row:IsShown() or row.rowTop >= Skada.Options.scrollOffset,
          "row " .. tostring(row.key) .. " scrolled over the page header")
      end
      local wheels
      for wheels = 1, 20 do Skada.Options.viewport.OnMouseWheel(nil, -1) end
      assert(rowForKey.mode:IsShown() and rowForKey.segment:IsShown(),
        "scrolling must bring the mode section into view")
      assert(rowForKey.deleteWindow:IsShown(), "window actions must be reachable by scrolling")
      assert(not rowForKey.combatHeader:IsShown(),
        "rows scrolled past the header band must hide, not draw over it")
      for i = 1, table.getn(winPage.rows) do
        row = winPage.rows[i]
        assert(not row:IsShown() or row.rowTop >= Skada.Options.scrollOffset,
          "row " .. tostring(row.key) .. " scrolled over the page header")
      end
      -- at the bottom of the page the thumb must sit at the end of its track
      local bar = Skada.Options.scrollbar
      assert(bar.offset == winPage.height - (424 - winPage.headerPad),
        "scroll did not reach the end of the page")
      assert(bar.track.height == 424, "track height must be set explicitly for GetHeight")
      assert(-bar.thumb.lastPointY + bar.thumb.height == bar.track.height,
        "thumb must reach the end of its track at max scroll")

      Skada.Options:SelectWindow(second)
      assert(Skada.Options.currentPage == "window")
      local function pickDropdown(row, value)
        TestDropdownInfos = {}
        row.chrome.OnClick()
        assert(row.menuFrame, "dropdown menu frame was not created for " .. tostring(row.key))
        row.menuFrame.initialize(row.menuFrame, 1)
        local j, info
        for j = 1, table.getn(TestDropdownInfos) do
          info = TestDropdownInfos[j]
          if info.value == value then info.func() return end
        end
        error("dropdown " .. tostring(row.key) .. " is missing a choice: " .. value)
      end
      local modeBefore = second.db.mode
      pickDropdown(rowForKey.mode, "healing")
      assert(second.db.mode == "healing", second.db.mode)
      pickDropdown(rowForKey.mode, "threat")
      assert(second.db.mode == "threat" and second.db.segment == "current",
        "live mode did not coerce the segment")
      pickDropdown(rowForKey.mode, modeBefore)
      assert(second.db.mode == modeBefore)

      -- an auto-named window follows its mode's name; a hand-set name stays
      local auto = Skada.UI:CreateNew()
      assert(auto.db.name == Skada.Modes:Get(auto.db.mode).title and not auto.db.nameIsCustom,
        "a new window should be auto-named from its mode")
      Skada.Options:SelectWindow(auto)
      pickDropdown(rowForKey.mode, "healing")
      assert(auto.db.mode == "healing" and auto.db.name == "Healing" and not auto.db.nameIsCustom,
        "switching mode did not rename the auto-named window")
      local k, nodeRow
      for k = 1, table.getn(Skada.Options.treeRows) do
        nodeRow = Skada.Options.treeRows[k]
        if nodeRow.node and nodeRow.node.window == auto then
          assert(nodeRow.node.label == "Healing",
            "settings tree did not pick up the mode-derived name")
        end
      end
      rowForKey.name.setValue("My meter")
      assert(auto.db.name == "My meter" and auto.db.nameIsCustom,
        "manual rename did not mark the window as custom-named")
      pickDropdown(rowForKey.mode, "threat")
      assert(auto.db.name == "My meter", "mode switch clobbered a custom window name")
      assert(Skada.UI:DeleteWindow(auto), "temporary window cleanup failed")
      Skada.Options:SelectWindow(second)

      pickDropdown(rowForKey.segment, 1)
      assert(second.db.segment == 1, second.db.segment)
      pickDropdown(rowForKey.segment, "total")
      assert(second.db.segment == "total", second.db.segment)
      pickDropdown(rowForKey.segment, "current")
      assert(second.db.segment == "current", second.db.segment)

      assert(rowForKey.hideTitle and rowForKey.combatMode and rowForKey.returnAfterCombat,
        "hide-title and combat-switch rows missing from the window page")
      local hideBefore = second.db.hideTitle
      rowForKey.hideTitle.setValue(not hideBefore)
      assert(second.db.hideTitle == not hideBefore and second.layoutDirty,
        "hide-title toggle did not mark the window layout dirty")
      rowForKey.hideTitle.setValue(hideBefore)

      local racBefore = second.db.returnAfterCombat
      rowForKey.returnAfterCombat.setValue(not racBefore)
      assert(second.db.returnAfterCombat == not racBefore)
      rowForKey.returnAfterCombat.setValue(racBefore)

      assert(rowForKey.snapSize, "snap size-match row missing from the window page")
      local sizeBefore = second.db.snapSize
      rowForKey.snapSize.setValue(not sizeBefore)
      assert(second.db.snapSize == not sizeBefore)
      rowForKey.snapSize.setValue(sizeBefore)

      local combatBefore = second.db.combatMode
      pickDropdown(rowForKey.combatMode, "threat")
      assert(second.db.combatMode == "threat", second.db.combatMode)
      assert(Skada.db.profile.combatMode == combatBefore,
        "secondary window combat mode leaked into the profile mirror")
      pickDropdown(rowForKey.combatMode, "")
      assert(second.db.combatMode == "", second.db.combatMode)

      rowForKey.name.setValue("Renamed meter")
      assert(second.db.name == "Renamed meter", second.db.name)

      local wasVisible = second.db.visible
      rowForKey.visible.setValue(false)
      assert(second.db.visible == false and not second.frame:IsShown(),
        "visibility checkbox did not hide the window")
      rowForKey.visible.setValue(true)
      assert(second.db.visible == true and second.frame:IsShown(),
        "visibility checkbox did not reshow the window")
      if not wasVisible then rowForKey.visible.setValue(false) end

      local newBtn
      for i = 1, table.getn(Skada.Options.treeRows) do
        local nodeRow = Skada.Options.treeRows[i]
        if type(nodeRow.node) == "table" and nodeRow.node.newWindow then newBtn = nodeRow break end
      end
      assert(newBtn, "+ New window tree node not found")
      newBtn.OnClick()
      local third = Skada.Options.selectedWindow
      assert(third and third ~= second and third ~= primary, "new window was not created and selected")
      assert(third.db.name == Skada.Modes:Get(third.db.mode).title,
        "unnamed window must default to its tracked mode's title")
      assert(Skada.UI.byID[third.db.id] == third, "created window missing from the registry")
      local windowNodes = 0
      for i = 1, table.getn(Skada.Options.treeRows) do
        local nodeRow = Skada.Options.treeRows[i]
        if type(nodeRow.node) == "table" and nodeRow.node.window then windowNodes = windowNodes + 1 end
      end
      assert(windowNodes == 3, windowNodes)

      Skada.Options:SelectWindow(third)
      rowForKey.deleteWindow.OnClick()
      assert(TestLastPopup == "SKADA_DELETE_WINDOW", tostring(TestLastPopup))
      assert(Skada.UI.byID[third.db.id] == third, "delete popup must not delete before accept")
      assert(StaticPopupDialogs.SKADA_DELETE_WINDOW, "delete dialog not registered")
      StaticPopupDialogs.SKADA_DELETE_WINDOW.OnAccept()
      assert(Skada.UI.byID[third.db.id] == nil, "accepted delete did not remove the window")
      assert(Skada.Options.selectedWindow == primary, "panel did not fall back after delete")
      windowNodes = 0
      for i = 1, table.getn(Skada.Options.treeRows) do
        local nodeRow = Skada.Options.treeRows[i]
        if type(nodeRow.node) == "table" and nodeRow.node.window then windowNodes = windowNodes + 1 end
      end
      assert(windowNodes == 2, windowNodes)

      local profile = Skada.db.profile
      assert(Skada.Common.FormatNumber(1234) == "1234")
      assert(Skada.Common.FormatNumber(12345) == "12k")
      assert(Skada.Common.FormatNumber(1234567) == "1.23m")
      assert(Skada.Common.FormatNumber(1234, "compact1") == "1.2k")
      assert(Skada.Common.FormatNumber(12345, "compact1") == "12.3k")
      assert(Skada.Common.FormatNumber(1234567, "compact1") == "1.2m")
      assert(Skada.Common.FormatNumber(1234, "full") == "1234")
      assert(Skada.Common.FormatNumber(12345, "full") == "12345")
      assert(Skada.Common.FormatNumber(1234567, "full") == "1234567")
      profile.numberFormat = "full"
      assert(Skada:FormatNumber(12345) == "12345")
      profile.numberFormat = "compact"
      assert(Skada:FormatNumber(12345) == "12k")

      Skada.Options:OpenPage("data")
      local numberRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "key") == "numberFormat" then numberRow = row break end
      end
      assert(numberRow, "number format dropdown row not found")
      pickDropdown(numberRow, "compact1")
      assert(profile.numberFormat == "compact1", profile.numberFormat)
      pickDropdown(numberRow, "compact")

      local maxRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "key") == "maxSegments" then maxRow = row break end
      end
      assert(maxRow, "max segments slider row not found")
      profile.maxSegments = 10
      GetCursorPosition = function() return 205, 300 end
      maxRow.track.left = 2
      maxRow.OnMouseDown()
      maxRow.OnMouseUp()
      assert(profile.maxSegments >= 1 and profile.maxSegments <= 50, profile.maxSegments)
      assert(table.getn(Skada.Data.history) <= profile.maxSegments,
        "history was not trimmed to the slider value")

      local resetRow
      for i = 1, table.getn(Skada.Options.pageCache.data.rows) do
        local row = Skada.Options.pageCache.data.rows[i]
        if rawget(row, "key") == "resetData" then resetRow = row break end
      end
      assert(resetRow, "reset data action row not found")
      table.insert(Skada.Data.history, Skada.Data.current)
      resetRow.OnClick()
      assert(TestLastPopup == "SKADA_RESET_DATA", tostring(TestLastPopup))
      assert(table.getn(Skada.Data.history) >= 1, "reset popup must not clear before accept")
      StaticPopupDialogs.SKADA_RESET_DATA.OnAccept()
      assert(table.getn(Skada.Data.history) == 0, "accepted reset did not clear history")

      local function fire(event)
        local handlers = Skada.eventHandlers[event]
        local h
        for h = 1, table.getn(handlers) do handlers[h]() end
      end
      assert(StaticPopupDialogs.SKADA_RESET_POLICY, "reset-policy dialog not registered")
      profile.resetOnEnterInstance = "no"
      fire("ZONE_CHANGED_NEW_AREA")
      table.insert(Skada.Data.history, Skada.Data.current)
      profile.resetOnEnterInstance = "yes"
      IsInInstance = function() return true end
      fire("ZONE_CHANGED_NEW_AREA")
      assert(table.getn(Skada.Data.history) == 0, "policy 'yes' did not reset on instance enter")
      profile.resetOnEnterInstance = "ask"
      IsInInstance = function() return false end
      fire("ZONE_CHANGED_NEW_AREA")
      IsInInstance = function() return true end
      fire("ZONE_CHANGED_NEW_AREA")
      assert(TestLastPopup == "SKADA_RESET_POLICY", tostring(TestLastPopup))
      table.insert(Skada.Data.history, Skada.Data.current)
      Skada.Data.active = true
      fire("ZONE_CHANGED_NEW_AREA")
      assert(table.getn(Skada.Data.history) == 1, "reset fired while a segment was active")
      Skada.Data.active = false
      IsInInstance = nil

      profile.resetOnJoinGroup = "yes"
      profile.resetOnLeaveGroup = "no"
      local savedGetNumRaidMembers = GetNumRaidMembers
      local savedGetNumPartyMembers = GetNumPartyMembers
      GetNumRaidMembers = function() return 0 end
      GetNumPartyMembers = function() return 0 end
      fire("RAID_ROSTER_UPDATE")
      table.insert(Skada.Data.history, Skada.Data.current)
      GetNumRaidMembers = function() return 10 end
      fire("RAID_ROSTER_UPDATE")
      assert(table.getn(Skada.Data.history) == 0, "policy 'yes' did not reset on group join")

      table.insert(Skada.Data.history, Skada.Data.current)
      GetNumRaidMembers = function() return 11 end
      fire("RAID_ROSTER_UPDATE")
      assert(table.getn(Skada.Data.history) == 1, "member joining an existing raid triggered a reset")
      profile.resetOnLeaveGroup = "yes"
      GetNumRaidMembers = function() return 10 end
      fire("RAID_ROSTER_UPDATE")
      assert(table.getn(Skada.Data.history) == 1, "member leaving an existing raid triggered a reset")

      GetNumRaidMembers = function() return 0 end
      fire("RAID_ROSTER_UPDATE")
      assert(table.getn(Skada.Data.history) == 0, "policy 'yes' did not reset on group leave")
      GetNumRaidMembers = savedGetNumRaidMembers
      GetNumPartyMembers = savedGetNumPartyMembers

      Skada.Options:OpenPage("window")
      Skada.Options:SelectWindow(second)
      local snapBefore = profile.snapDistance
      GetCursorPosition = function() return 205, 300 end
      rowForKey.snapDistance.track.left = 2
      rowForKey.snapDistance.OnMouseDown()
      rowForKey.snapDistance.OnMouseUp()
      assert(second.db.snapDistance ~= nil and second.db.snapDistance >= 0 and second.db.snapDistance <= 40,
        second.db.snapDistance)
      assert(profile.snapDistance == snapBefore,
        "secondary window snap key leaked into the profile mirror")
      Skada.Options:SelectWindow(primary)
      GetCursorPosition = function() return 500, 300 end
      rowForKey.snapDistance.OnMouseDown()
      rowForKey.snapDistance.OnMouseUp()
      assert(profile.snapDistance == primary.db.snapDistance,
        "primary window snap key was not mirrored into the profile")

      local miniRow
      for i = 1, table.getn(Skada.Options.controls) do
        local row = Skada.Options.controls[i]
        if rawget(row, "key") == "minimap" then miniRow = row break end
      end
      assert(miniRow, "minimap checkbox row not found")
      miniRow.setValue(false)
      assert(Skada.db.profile.minimap.show == false)
      assert(not Skada.Options.minimapButton:IsShown())
      miniRow.setValue(true)
      assert(Skada.db.profile.minimap.show == true)
      assert(Skada.Options.minimapButton:IsShown())

      Skada.Options:Toggle()
      assert(not Skada.Options.frame:IsShown())
      Skada.Options:Toggle()
      assert(Skada.Options.frame:IsShown())
      Skada.Options.frame:Hide()

      Skada.UI:SetActive(primary)
      assert(Skada.UI:DeleteWindow(second))
    ''')