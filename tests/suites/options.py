"""Suite: options - profile defaults, the bespoke settings dialog, its controls, reset policies, minimap."""

from harness import Context


def run(ctx: Context):
    skada = ctx.skada
    assert skada.db.profile.classColors is True
    assert skada.db.profile.fontName == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf"
    assert skada.db.profile.minimap.show is True
    assert skada.Options.minimapButton is not None
    assert skada.db.profile.updateRate is None
    assert skada.db.profile.smoothBars is None
    assert skada.db.profile.barSpeed is None

    ctx.run(r'''
      local function countKeys(t)
        local count = 0
        local key
        for key in pairs(t) do count = count + 1 end
        return count
      end

      -- tests/stubs.lua installs RollFor's captures-only string.match before
      -- the addon loads, as the real client does; core.compat must have
      -- probed and swapped in a correct one, or Skada's own slash-command
      -- parsing (Common.Match binds it at load) returns nil for every
      -- capture-less pattern.
      assert(strmatch("AceConfigDialog-3.0", "[A-Za-z]%-[0-9]") == "g-3",
        "capture-less strmatch did not return the whole match")
      assert(strmatch("v1 v2", "v(%d)", 3) == "2", "strmatch ignored its init argument")
      local settingKey, settingValue = strmatch("width=700", "^(%w+)=(%w+)$")
      assert(settingKey == "width" and settingValue == "700", "strmatch dropped a capture")
      assert(strmatch("abc", "%d") == nil, "strmatch returned a value for a non-match")

      -- Script hooks chain by hand and pass the client's arguments through:
      -- the client's own HookScript drops them.
      local hooked = CreateFrame("Frame", nil, UIParent)
      local seenFirst, seenSecond
      hooked:SetScript("OnMouseUp", function(frame, mouseButton) seenFirst = { frame, mouseButton } end)
      SkadaCompat.AppendScript(hooked, "OnMouseUp", function(frame, mouseButton) seenSecond = { frame, mouseButton } end)
      hooked.OnMouseUp(hooked, "LeftButton")
      assert(seenFirst and seenFirst[1] == hooked and seenFirst[2] == "LeftButton",
        "original handler lost its arguments")
      assert(seenSecond and seenSecond[1] == hooked and seenSecond[2] == "LeftButton",
        "appended handler did not receive the arguments")

      -- The SetParent shim: SetParent into an AceGUI-owned frame (`.obj` set)
      -- re-derives strata and level from the new parent, subtree included,
      -- but keeps larger level gaps set on purpose. Plain frames keep the
      -- client's native reparenting. (The shim exists for BigDebuffs' own
      -- Ace3 copy now; Skada's dialog builds everything under its root
      -- directly and never reparents.)
      local host = CreateFrame("Frame", nil, UIParent)
      host.obj = { type = "SimpleGroup" }
      host:SetFrameStrata("DIALOG")
      host:SetFrameLevel(7)
      local moved = CreateFrame("Frame", nil, UIParent)
      local inner = CreateFrame("Button", nil, moved)
      assert(moved:GetFrameStrata() == "MEDIUM" and moved:GetFrameLevel() == 2,
        "stub frames must start with UIParent's strata and level + 1")
      moved:SetParent(host)
      assert(moved:GetFrameStrata() == "DIALOG" and moved:GetFrameLevel() == 8,
        "SetParent must re-derive the moved frame's strata and level")
      assert(inner:GetFrameStrata() == "DIALOG" and inner:GetFrameLevel() == 9,
        "SetParent must carry the moved frame's subtree along")
      local lowHost = CreateFrame("Frame", nil, UIParent)
      lowHost.obj = { type = "SimpleGroup" }
      local spaced = CreateFrame("Frame", nil, UIParent)
      local spacedInner = CreateFrame("Frame", nil, spaced)
      spacedInner:SetFrameLevel(spaced:GetFrameLevel() + 3)
      assert(spacedInner:GetFrameLevel() == 5)
      spaced:SetParent(lowHost)
      assert(spaced:GetFrameLevel() == 3 and spacedInner:GetFrameLevel() == 5,
        "SetParent must keep a deliberate level gap when nothing is inverted")
      local plainHost = CreateFrame("Frame", nil, UIParent)
      plainHost:SetFrameStrata("DIALOG")
      local untouched = CreateFrame("Frame", nil, UIParent)
      untouched:SetParent(plainHost)
      assert(untouched:GetFrameStrata() == "MEDIUM" and untouched:GetFrameLevel() == 2,
        "SetParent into a frame AceGUI does not own must leave layering alone")

      -- Size reads. An anchor-sized frame reports its rendered size in
      -- screen units on this client (size x effective scale); for AceGUI's
      -- frames (BigDebuffs' copy) an explicit size wins and a rendered rect
      -- is divided back, other frames get the client's raw answer.
      local rendered = CreateFrame("Frame", nil, UIParent)
      rendered.obj = { type = "SimpleGroup" }
      rawset(rendered, "stubScale", 0.71)
      rawset(rendered, "width", 604)              -- 850.7 units as the client reports them
      assert(math.abs(rendered:GetWidth() - 850.7) < 0.1,
        "rendered rect must be divided by the effective scale: " .. tostring(rendered:GetWidth()))
      rendered:SetWidth(540)
      assert(rendered:GetWidth() == 540, "an explicit size must win for AceGUI frames")
      local rawFrame = CreateFrame("Frame", nil, UIParent)
      rawset(rawFrame, "stubScale", 0.71)
      rawset(rawFrame, "width", 604)
      assert(rawFrame:GetWidth() == 604, "frames AceGUI does not own keep the client's raw answer")
    ''')

    # ------------------------------------------------------------------
    # The bespoke dialog: chrome, sidebar, pane, layout.
    # ------------------------------------------------------------------
    ctx.run(r'''
      local Dialog = Skada.OptionsDialog
      local Controls = Skada.OptionsControls

      -- Opening is synchronous: no deferred OnUpdate tick, the frame is up
      -- the moment Open returns.
      Skada.Options:Open()
      local dialog = Dialog.Frame()
      assert(dialog and dialog:GetName() == "SkadaOptionsFrame",
        "opening settings did not create SkadaOptionsFrame")
      assert(dialog:IsShown(), "settings dialog did not show")
      assert(dialog:GetFrameStrata() == "HIGH",
        "dialog root must sit at HIGH, got " .. tostring(dialog:GetFrameStrata()))
      assert(rawget(dialog, "stubToplevel") == false,
        "dialog root must not be toplevel: a click would re-raise it over its children")

      -- Every frame under the root must share its strata and out-level its
      -- parent; otherwise the root's translucent backdrop draws over the
      -- subtree and, being mouse-enabled, takes its clicks. The select popup
      -- and the input driver are checked separately (popup rides at DIALOG on
      -- purpose); the walk here runs before either exists.
      local rootStrata = dialog:GetFrameStrata()
      local function checkSubtree(frame, checked)
        local children = { frame:GetChildren() }
        local childIndex, child
        for childIndex = 1, table.getn(children) do
          child = children[childIndex]
          assert(child:GetFrameStrata() == rootStrata,
            "frame under the dialog kept strata " .. tostring(child:GetFrameStrata()))
          -- The style kit's drop shadow deliberately sits one level BELOW
          -- its frame (it draws behind it); every real child must out-level.
          if rawget(frame, "skadaShadow") ~= child then
            assert(child:GetFrameLevel() > frame:GetFrameLevel(),
              "frame under the dialog does not out-level its parent")
          end
          checked = checkSubtree(child, checked + 1)
        end
        return checked
      end
      local framesChecked = checkSubtree(dialog, 0)
      assert(framesChecked > 20, "dialog subtree walk found only " .. framesChecked .. " frames")

      -- Chrome: the default UI's own dialog-box frame, untinted (no black
      -- wash, no drop shadow), no inset panes inside it, the header
      -- ribbon's gold title, a red panel Close button and the round X.
      local Style = Skada.UIStyle
      assert(dialog.backdrop == Style.DIALOG_BACKDROP and dialog.backdropR == 1
        and dialog.backdropA == 1, "dialog root must wear the untinted dialog-box frame")
      assert(rawget(dialog, "skadaShadow") == nil, "classic chrome draws no drop shadow")
      assert(dialog.dialogTitle.textValue == "Skada" and dialog.dialogTitle.textR == Style.GOLD_R,
        "dialog must carry the gold header-ribbon title")
      -- One surface inside the frame: no inset boxes around the sidebar or
      -- the page, just a hairline between them.
      assert(dialog.sidebar.backdrop == nil and dialog.pane.backdrop == nil,
        "sidebar and pane must not be boxed")
      assert(dialog.divider and dialog.divider.width == 1
        and dialog.divider.vertexR == Style.RULE_R,
        "the sidebar and page must be separated by a single hairline")
      assert(dialog.closeButton and dialog.closeButton.frameType == "Button"
        and dialog.closeButton.textValue == "Close",
        "dialog must carry a panel Close button")
      assert(dialog.closeX and rawget(dialog.closeX, "normalTexture") == Style.CLOSE_BUTTON_TEXTURE,
        "dialog must carry the round panel X")
      assert(dialog.versionText and dialog.versionText.textValue == "Skada " .. Skada.version,
        "dialog must show the addon version in its corner")

      -- Sidebar: the three profile pages first, then the Windows header (a
      -- plain Frame, so its label takes no clicks) with its plus button,
      -- then one row per meter window.
      local PAGE_ROWS = 3
      local rows = dialog.sidebar.rows
      assert(table.getn(rows) == PAGE_ROWS + 1 + table.getn(Skada.UI.windows),
        "sidebar must hold the pages + the Windows header + one row per window, got "
        .. table.getn(rows))
      assert(rows[1].text.textValue == "General" and rows[1].groupKey == "general",
        "first sidebar row must be General")
      assert(rows[2].text.textValue == "Appearance" and rows[2].groupKey == "appearance",
        "second sidebar row must be Appearance")
      assert(rows[3].text.textValue == "Data" and rows[3].groupKey == "data",
        "third sidebar row must be Data")
      local pageRowIndex
      for pageRowIndex = 1, PAGE_ROWS do
        assert(rows[pageRowIndex].frameType == "Button", "page rows must be clickable")
        assert(rows[pageRowIndex].text.textR == Style.GOLD_R and rows[pageRowIndex].text.textG == Style.GOLD_G,
          "page rows must read in gold")
      end
      assert(rows[1].marker:IsShown(), "the selected page's row must show its marker")
      assert(not rows[2].marker:IsShown() and not rows[3].marker:IsShown(),
        "unselected page rows must not light up")
      local headerRow = rows[PAGE_ROWS + 1]
      assert(headerRow.text.textValue == "Windows", "the Windows header must follow the pages")
      assert(headerRow.frameType ~= "Button", "the Windows header must not take clicks")
      local plus = headerRow.plusButton
      assert(plus and rawget(plus, "normalTexture") == "Interface\\Buttons\\UI-PlusButton-UP",
        "the Windows header must carry a plus button")
      local windowRowIndex
      for windowRowIndex = PAGE_ROWS + 2, table.getn(rows) do
        assert(rows[windowRowIndex].frameType == "Button", "window rows must be clickable")
        -- Unselected window rows read in white; the selected row (General
        -- here) lights the quest-log highlight and turns gold.
        assert(not rows[windowRowIndex].marker:IsShown(), "unselected rows must not light up")
        assert(rows[windowRowIndex].text.textR == 1 and rows[windowRowIndex].text.textG == 1,
          "unselected window rows must read in white")
        assert(rows[windowRowIndex].text.lastPointX == 20,
          "window rows must sit indented under the Windows header")
      end
      assert(rows[1].marker.texture == Style.ROW_HIGHLIGHT_TEXTURE,
        "the selection marker must be the quest-log highlight")

      -- Pane: every page opens with its title row, then renders each of its
      -- schema rows as a control laid out arithmetically inside the scroll
      -- child. General is the short page: tracking and client toggles.
      local function pageTypes()
        local counts = {}
        local controlIndex, control
        for controlIndex = 1, table.getn(dialog.controls) do
          control = dialog.controls[controlIndex]
          assert(control.spec and control.spec.type, "a pane control lost its spec reference")
          counts[control.spec.type] = (counts[control.spec.type] or 0) + 1
        end
        return counts
      end
      local general = pageTypes()
      assert(table.getn(dialog.controls) == 11,
        "General pane did not build every control: " .. table.getn(dialog.controls))
      assert(general.title == 1 and general.header == 3 and general.toggle == 5 and general.range == 2,
        "General must be a title, three headings, five toggles and the two snap sliders")
      assert(not dialog.titleAction:IsShown(), "profile pages have no title-row action")
      assert(dialog.controls[1].spec.type == "title" and dialog.controls[1].spec.name == "General"
        and dialog.controls[1].label.textValue == "General"
        and dialog.controls[1].description.textValue ~= nil,
        "every page must open with its titled heading")
      assert(dialog.content:GetWidth() == 518,
        "scroll child must carry the arithmetic width, got " .. tostring(dialog.content:GetWidth()))
      assert(dialog.scrollframe:GetName() == "SkadaOptionsScrollFrame",
        "pane scroll frame must be named (its template scrollbar is <name>ScrollBar)")
      assert(dialog.scrollbar == _G.SkadaOptionsScrollFrameScrollBar,
        "the pane scroll frame must use its template's own scrollbar")
      assert(dialog.scrollframe:IsMouseWheelEnabled(),
        "the pane scroll frame must scroll on the mouse wheel")
      -- A page that fits the pane shows no scrollbar; one that overflows
      -- brings it back (the height is arithmetic, so it is decided at build).
      assert(not dialog.scrollbar:IsShown(), "a page that fits must not show a scrollbar")
      assert(dialog.content:GetHeight() <= Dialog.SCROLL_VIEW_HEIGHT)
      local header = dialog.controls[2]
      assert(header.spec.type == "header" and header.label.lastPoint == "LEFT"
        and header.rule and header.rule.lastPoint == "RIGHT",
        "a section heading must sit at the left with one rule trailing right")

      -- Layout: rows hold only controls of one kind. The three tracking
      -- toggles share a row (x = 0, 170, 340 at one y); the heading that
      -- follows starts a new, lower row.
      local function findControl(key)
        local controlIndex, control
        for controlIndex = 1, table.getn(dialog.controls) do
          control = dialog.controls[controlIndex]
          if control.spec.name == key then return control end
        end
      end
      local mergePets = findControl("Merge pets into owners")
      local trackAll = findControl("Track all nearby sources")
      local nampower = findControl("Use Nampower combat events")
      assert(mergePets.lastPointX == 0 and trackAll.lastPointX == 170 and nampower.lastPointX == 340,
        "toggles must flow three to a row")
      assert(mergePets.lastPointY == trackAll.lastPointY and trackAll.lastPointY == nampower.lastPointY,
        "toggles in one row must share a y")
      assert(findControl("Minimap and logging").lastPointY < nampower.lastPointY,
        "a heading must start a new row below the toggles")
      assert(nampower.disabled == true and nampower.alpha < 1,
        "the Nampower toggle must render dimmed while Nampower is absent")
      assert(mergePets.alpha == 1, "an applicable toggle must not be dimmed")

      -- Data holds the execute button: the panel button sits inset in its
      -- row rather than on the cell's edge, and a full-width row keeps it at
      -- a button's width.
      dialog.sidebar.rows[3].OnClick(dialog.sidebar.rows[3])
      assert(Dialog.selectedGroup == "data", "clicking the Data row did not select it")
      assert(rows[3].marker:IsShown() and not rows[1].marker:IsShown(),
        "the sidebar marker must move to the clicked page")
      assert(table.getn(dialog.controls) == 10,
        "Data pane did not build every control: " .. table.getn(dialog.controls))
      local reset = findControl("Reset all data")
      assert(reset and reset.spec.type == "execute", "Data must carry the reset button")
      assert(reset.lastPointX == 4 and reset.lastPointY < 0,
        "execute button must be placed at its cell inset")
      assert(reset:GetWidth() == 200, "full-width execute must keep a button's width")
      local data = pageTypes()
      assert(data.select == 3 and data.range == 1 and data.note == 1,
        "Data must carry the three reset policies, the history slider and its note")
      local enterInstance = findControl("On entering an instance")
      local joinGroup = findControl("On joining a group")
      assert(enterInstance.lastPointX == 0 and joinGroup.lastPointX == 170
        and enterInstance.lastPointY == joinGroup.lastPointY,
        "selects must flow three to a row")

      -- Appearance holds everything shared by every window, with dependents
      -- dimmed behind their toggles: the custom bar color only applies with
      -- class colors off, and a commit on the toggle undims it at once.
      Dialog:Select("appearance")
      assert(table.getn(dialog.controls) == 18,
        "Appearance pane did not build every control: " .. table.getn(dialog.controls))
      local appearance = pageTypes()
      assert(appearance.select == 4 and appearance.color == 4 and appearance.toggle == 6,
        "Appearance must carry the shared dropdowns, swatches and toggles")
      local classColors = findControl("Class colors")
      local barColor = findControl("Custom bar color")
      assert(classColors.lastPointY == barColor.lastPointY and barColor.lastPointX == 170,
        "a toggle and its color swatch share a row")
      assert(Skada.db.profile.classColors ~= false)
      assert(barColor.disabled == true and barColor.alpha < 1,
        "the custom bar color must be dimmed while class colors are on")
      classColors.OnClick(classColors)
      assert(Skada.db.profile.classColors == false, "the toggle click did not commit")
      assert(barColor.disabled == false and barColor.alpha == 1,
        "committing the toggle must undim its dependent without a rebuild")
      classColors.OnClick(classColors)
      assert(Skada.db.profile.classColors == true and barColor.disabled == true)
      -- A dimmed control ignores clicks.
      barColor.OnClick(barColor)
      assert(not ColorPickerFrame:IsShown(), "a dimmed swatch must not open the picker")
      local framesAfterPages = checkSubtree(dialog, 0)
      assert(framesAfterPages > 30, "dialog subtree walk found only " .. framesAfterPages .. " frames")

      -- Pooling: switching back to a page already seen creates no frames
      -- (a frame on this client is never released), and the controls a page
      -- gets are the ones it was rendered with before.
      local created = 0
      local savedCreateFrame = CreateFrame
      CreateFrame = function(...)
        created = created + 1
        return savedCreateFrame(...)
      end
      Dialog:Select("general")
      Dialog:Select("appearance")
      Dialog:Select("data")
      CreateFrame = savedCreateFrame
      assert(created == 0, "revisiting pages created " .. created .. " frames instead of reusing pooled ones")
      assert(findControl("Class colors") == nil and findControl("Reset all data") == reset,
        "the Data page must get back the pooled controls it was rendered with")

      -- Opening shows the selection highlight on the active window without
      -- ever replacing its configured border color.
      local primary = Skada.UI:GetPrimary()
      assert(Skada.Options.selectedWindow == primary)
      assert(Skada.UI.visualActive == primary,
        "opening settings did not show its window selection")
      Skada.Options:SelectWindow(primary)
      local configuredBorder = Skada.db.profile.windowBorderColor
      local borderEdges = rawget(primary.frame, "skadaBorderEdges")
      assert(borderEdges and borderEdges[1].vertexR == configuredBorder[1] and
        borderEdges[1].vertexG == configuredBorder[2] and
        borderEdges[1].vertexB == configuredBorder[3],
        "selecting a window replaced its configured border color")

      -- Navigating to a window's pane builds its rows; the subtree layering
      -- must hold after the rebuild too.
      Dialog:Open("window_" .. tostring(primary.db.id))
      assert(table.getn(dialog.controls) == 21,
        "window pane did not build every control: " .. table.getn(dialog.controls))
      -- A window page fits the pane: no scrolling to reach any row.
      assert(dialog.content:GetHeight() <= Dialog.SCROLL_VIEW_HEIGHT,
        "window page overflows the pane: " .. tostring(dialog.content:GetHeight()))
      checkSubtree(dialog, 0)
      assert(dialog.controls[1].spec.type == "title" and dialog.controls[1].spec.name == primary.db.name,
        "a window page must be titled with the window's name")
      local litRows = 0
      for windowRowIndex = 1, table.getn(dialog.sidebar.rows) do
        local sidebarRow = dialog.sidebar.rows[windowRowIndex]
        if sidebarRow.marker and sidebarRow.marker:IsShown() then
          litRows = litRows + 1
          assert(sidebarRow.groupKey == "window_" .. tostring(primary.db.id),
            "only the selected window's row may light up")
          assert(sidebarRow.text.textR == Style.GOLD_R and sidebarRow.text.textG == Style.GOLD_G,
            "the selected window row must turn gold")
        end
      end
      assert(litRows == 1, "exactly one sidebar row must be lit, got " .. litRows)
      local window = pageTypes()
      assert(window.input == 1 and window.range == 7 and window.header == 3 and window.execute == nil,
        "window pane must hold its input, seven sliders, three headings and no in-page button")
      assert(dialog.controls[1].description.textValue ~= nil
        and string.find(dialog.controls[1].description.textValue, "Appearance"),
        "a window page's subtitle must point at Appearance for the shared look")
      local widthControl = findControl("Width")
      local rowsControl = findControl("Rows")
      assert(widthControl.lastPointX == 0 and rowsControl.lastPointX == 170
        and widthControl.lastPointY == rowsControl.lastPointY,
        "sliders must flow three to a row")

      -- Dependents on a window page: size matching dims behind the snap
      -- toggle, the segment behind a live mode. Snap distance and gap are
      -- not here: they live on General, once for every window.
      assert(findControl("Snap distance") == nil and findControl("Snap gap") == nil,
        "snap distance and gap must not sit on a window page")
      local snapToggle = findControl("Snap to edges and windows")
      local snapSize = findControl("Match size when snapped")
      assert(primary.db.snap and snapSize.disabled == false)
      snapToggle.OnClick(snapToggle)
      assert(primary.db.snap == false and snapSize.disabled == true,
        "size matching must dim while snapping is off")
      snapToggle.OnClick(snapToggle)
      assert(primary.db.snap == true and snapSize.disabled == false)
      assert(findControl("Return after combat") == nil,
        "the retired return toggle must not render: a combat mode always returns")

      -- The delete action is the button on the page's title row, top-right
      -- of the pane and never scrolled away; it is bound to the page's
      -- title-row spec.
      assert(dialog.titleAction:IsShown() and dialog.titleAction.textValue == "Delete window",
        "a window page must show the Delete window button on its title row")
      assert(dialog.titleAction.spec and dialog.titleAction.spec.placement == "title")
      assert(dialog.titleAction.lastPoint == "TOPRIGHT" and dialog.titleAction.lastRelativeTo == dialog.pane,
        "the title-row action must anchor to the pane's top-right")
      Dialog:Open("general")
      assert(not dialog.titleAction:IsShown(), "General must hide the title-row action")
    ''')

    # ------------------------------------------------------------------
    # The control renderers, driven directly against synthetic specs.
    # ------------------------------------------------------------------
    ctx.run(r'''
      local Controls = Skada.OptionsControls
      local dialog = Skada.OptionsDialog.Frame()
      local anchor = CreateFrame("Frame", nil, UIParent)

      -- Sliders: min/max/step reach the frame, the value lives in a plain
      -- FontString (no EditBox -- the blank-value-box bug class is gone by
      -- design), driving OnValueChanged commits through spec.set with the
      -- step snapped, and the initial paint must NOT commit.
      local sliderValue = 3
      local sliderSetCount = 0
      local rangeSpec = {
        type = "range", name = "Test range", min = 0, max = 8, step = 1,
        get = function() return sliderValue end,
        set = function(value) sliderValue = value; sliderSetCount = sliderSetCount + 1 end,
      }
      local rangeFrame = Controls.Render(anchor, rangeSpec, 170)
      local slider = rangeFrame.slider
      assert(slider and slider.frameType == "Slider", "range must build a Slider frame")
      local sliderMin, sliderMax = slider:GetMinMaxValues()
      assert(sliderMin == 0 and sliderMax == 8, "slider min/max did not reach the frame")
      assert(slider:GetValueStep() == 1, "slider step did not reach the frame")
      assert(slider:GetOrientation() == "HORIZONTAL")
      assert(slider:GetThumbTexture() == "Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
      assert(slider:IsMouseWheelEnabled(), "slider must step on the mouse wheel")
      assert(slider:GetValue() == 3, "slider must show the current value")
      assert(sliderSetCount == 0, "the initial paint must not commit")
      assert(rangeFrame.valueText:GetText() == "3", "value text must show the plain value")
      slider:GetScript("OnValueChanged")(slider, 8)
      assert(sliderValue == 8, "driving OnValueChanged did not commit")
      assert(rangeFrame.valueText:GetText() == "8", "value text did not repaint with the commit")
      slider:GetScript("OnValueChanged")(slider, 3.6)
      assert(sliderValue == 4, "values must snap to the step, got " .. tostring(sliderValue))

      -- A percent range (0..1) displays as 0..100%.
      local percentValue = 0.4
      local percentSpec = {
        type = "range", name = "Test percent", isPercent = true,
        min = 0, max = 1, step = 0.01,
        get = function() return percentValue end,
        set = function(value) percentValue = value end,
      }
      local percentFrame = Controls.Render(anchor, percentSpec, 170)
      assert(percentFrame.valueText:GetText() == "40%",
        "percent value must render as a plain percentage, got "
        .. tostring(percentFrame.valueText:GetText()))
      percentFrame.slider:GetScript("OnValueChanged")(percentFrame.slider, 0.75)
      assert(math.abs(percentValue - 0.75) < 1e-9,
        "percent commit wrong: " .. tostring(percentValue))
      assert(percentFrame.valueText:GetText() == "75%")

      -- Toggles: the check mark follows the value, the click flips it.
      local toggleValue = true
      local toggleSpec = {
        type = "toggle", name = "Test toggle",
        get = function() return toggleValue end,
        set = function(value) toggleValue = value end,
      }
      local toggleButton = Controls.Render(anchor, toggleSpec, 170)
      assert(toggleButton.frameType == "Button")
      assert(toggleButton.checkMark.texture == Skada.UIStyle.CHECK_MARK_TEXTURE,
        "toggle must draw the default UI's check mark")
      assert(toggleButton.checkMark:IsShown(), "check mark must show for a true value")
      toggleButton.OnClick(toggleButton)
      assert(toggleValue == false, "toggle click did not commit the flipped value")
      assert(not toggleButton.checkMark:IsShown(), "check mark must hide for a false value")
      toggleButton.OnClick(toggleButton)
      assert(toggleValue == true)

      -- Selects: the click opens the Skada-owned popup above the dialog,
      -- one entry per choice in sorting order with the marker on the current
      -- value; picking an entry commits and closes.
      local selectValue = "a"
      local selectSpec = {
        type = "select", name = "Test select",
        values = function() return { a = "Alpha", b = "Beta", c = "Gamma" } end,
        sorting = function() return { "a", "b", "c" } end,
        get = function() return selectValue end,
        set = function(value) selectValue = value end,
      }
      local selectButton = Controls.Render(anchor, selectSpec, 170)
      assert(selectButton.frameType == "Button")
      assert(selectButton.valueText:GetText() == "Alpha")
      selectButton.OnClick(selectButton)
      local popup = dialog.selectPopup
      assert(popup and popup:IsShown(), "select click did not open the popup")
      assert(popup:GetParent() == dialog, "popup must be parented to the dialog root, not the scroll child")
      assert(popup:GetFrameStrata() == "DIALOG",
        "popup must ride above the HIGH dialog, got " .. tostring(popup:GetFrameStrata()))
      assert(table.getn(popup.entries) == 3, "popup must hold one entry per choice")
      assert(popup.backdrop == Skada.UIStyle.MENU_BACKDROP,
        "popup must wear the default UI's dropdown list frame")
      assert(popup.entries[1].marker.texture == Skada.UIStyle.CHECK_MARK_TEXTURE,
        "the current value's marker must be the default UI's check mark")
      assert(popup.entries[1].text.textValue == "Alpha"
        and popup.entries[2].text.textValue == "Beta"
        and popup.entries[3].text.textValue == "Gamma", "popup labels must follow values()")
      assert(popup.entries[1].marker:IsShown(), "the current value's entry must carry the marker")
      assert(not popup.entries[2].marker:IsShown(), "other entries must not carry the marker")
      popup.entries[3].OnClick(popup.entries[3])
      assert(selectValue == "c", "picking an entry did not commit its value")
      assert(not popup:IsShown(), "picking an entry must close the popup")
      assert(selectButton.valueText:GetText() == "Gamma",
        "picking an entry must repaint the dropdown without changing pages")
      selectButton.OnClick(selectButton)
      assert(popup:IsShown() and popup.entries[3].marker:IsShown(),
        "reopening must repaint the marker onto the current value")
      -- A click anywhere outside the open list (the dropdown included)
      -- lands on the catcher under it and closes the list, nothing picked.
      local catcher = popup.catcher
      assert(catcher and catcher:IsShown(), "an open list must raise its click catcher")
      assert(catcher:GetFrameStrata() == "DIALOG" and catcher:GetFrameLevel() < popup:GetFrameLevel(),
        "the click catcher must sit above the dialog but under the list")
      assert(popup.entries[1]:GetFrameLevel() > catcher:GetFrameLevel(),
        "the list's entries must sit above the click catcher")
      catcher.OnMouseDown(catcher)
      assert(not popup:IsShown() and not catcher:IsShown(), "a click outside the list did not close it")
      assert(selectValue == "c", "closing the list by clicking away must not change the value")
      selectButton.OnClick(selectButton)
      popup:Hide()
      assert(not catcher:IsShown(), "closing the list must drop its click catcher")

      -- The shared popup must repaint the dropdown that opened it, using
      -- the committed value even when the setter normalizes the selection.
      local otherValue = "a"
      local otherButton = Controls.Render(anchor, {
        type = "select", name = "Other select",
        values = selectSpec.values, sorting = selectSpec.sorting,
        get = function() return otherValue end,
        set = function(value) otherValue = value == "c" and "b" or value end,
      }, 170)
      otherButton.OnClick(otherButton)
      popup.entries[3].OnClick(popup.entries[3])
      assert(otherButton.valueText:GetText() == "Beta",
        "dropdown must display the committed value after normalization")
      assert(selectButton.valueText:GetText() == "Gamma",
        "reused popup repainted the wrong dropdown")
      selectButton.OnClick(selectButton)
      popup.entries[1].OnClick(popup.entries[1])
      assert(selectButton.valueText:GetText() == "Alpha")
      assert(otherButton.valueText:GetText() == "Beta")

      -- Colors: the swatch click shows Blizzard's shared picker above this
      -- dialog, with the compat OnShow hook carrying the layering down to
      -- the Okay/Cancel children (they keep their load-time strata/levels on
      -- this client, and the picker otherwise swallows their clicks). The
      -- picker's .func drives spec.set; hiding restores toplevel.
      assert(not ColorPickerFrame:IsShown())
      assert(ColorPickerOkayButton:GetFrameStrata() == "DIALOG",
        "color picker stub must start at DIALOG like the XML frame")
      local colorRed, colorGreen, colorBlue = 1, 0.5, 0.25
      local colorSpec = {
        type = "color", name = "Test color",
        get = function() return colorRed, colorGreen, colorBlue end,
        set = function(r, g, b) colorRed, colorGreen, colorBlue = r, g, b end,
      }
      local colorButton = Controls.Render(anchor, colorSpec, 170)
      colorButton.OnClick(colorButton)
      assert(ColorPickerFrame:IsShown(), "swatch click did not show the color picker")
      assert(ColorPickerFrame:GetFrameStrata() == "DIALOG")
      assert(ColorPickerFrame:GetFrameLevel() > dialog:GetFrameLevel() + 40,
        "picker must be bumped well above the dialog's deepest frame")
      local pickerChildren = { ColorPickerFrame:GetChildren() }
      assert(table.getn(pickerChildren) == 3)
      local pickerIndex
      for pickerIndex = 1, 3 do
        assert(pickerChildren[pickerIndex]:GetFrameStrata() == "DIALOG",
          "color picker child kept strata " .. tostring(pickerChildren[pickerIndex]:GetFrameStrata()))
        assert(pickerChildren[pickerIndex]:GetFrameLevel() > ColorPickerFrame:GetFrameLevel(),
          "color picker child does not out-level the picker: its buttons would be unclickable")
      end
      assert(ColorPickerFrame:IsToplevel() == false,
        "picker must not re-raise itself over its buttons while shown")
      ColorPickerFrame:SetColorRGB(0.2, 0.4, 0.6)
      ColorPickerFrame.func()
      assert(colorRed == 0.2 and colorGreen == 0.4 and colorBlue == 0.6,
        "the picker's Okay func did not commit the picked color")
      ColorPickerFrame.cancelFunc()
      assert(colorRed == 1 and colorGreen == 0.5 and colorBlue == 0.25,
        "the picker's cancelFunc did not restore the previous color")
      ColorPickerFrame:Hide()
      assert(ColorPickerFrame:IsToplevel() == true,
        "picker's toplevel flag must be restored on hide")

      -- Executes: the click calls spec.func().
      local executed = false
      local executeSpec = {
        type = "execute", name = "Test execute",
        func = function() executed = true end,
      }
      local executeButton = Controls.Render(anchor, executeSpec, 510)
      assert(executeButton.frameType == "Button" and executeButton.textValue == "Test execute",
        "execute must be a panel button carrying its own label")
      assert(executeButton.cellOffsetX == 4 and executeButton.cellOffsetY == 3,
        "execute must ask the dialog for its row inset")
      executeButton.OnClick(executeButton)
      assert(executed, "execute click did not run its func")

      -- Inputs: the value is NEVER set at build time (preset EditBox text
      -- set before the first render comes up blank on this client); it is
      -- queued and applied by the one-shot driver once a render pass has
      -- placed the box.
      local inputValue = "Preset name"
      local inputSpec = {
        type = "input", name = "Test input", width = "full",
        get = function() return inputValue end,
        set = function(value) inputValue = value end,
      }
      local inputFrame = Controls.Render(anchor, inputSpec, 170)
      local box = inputFrame.box
      assert(box.frameType == "EditBox")
      assert(box:GetText() == nil, "the input must not be filled at build time")
      assert(rawget(box, "skadaDisplayFrames") ~= nil, "the input must be queued for display")
      -- Unplaced: the pump must wait (within the frame budget).
      Controls.PumpInputDisplay()
      assert(box:GetText() == nil, "the pump must wait until a render pass has placed the box")
      rawset(box, "left", 100)                    -- placed
      Controls.PumpInputDisplay()
      assert(box:GetText() == "Preset name", "the pump did not apply the queued value")
      assert(rawget(box, "skadaDisplayText") == "Preset name",
        "the applied value must be remembered as the revert point")
      assert(rawget(box, "stubFocused") == false, "the pump must leave the box unfocused")
      -- Enter commits, Escape reverts to the last displayed value.
      box:SetText("Typed name")
      box:GetScript("OnEnterPressed")(box)
      assert(inputValue == "Typed name", "Enter did not commit the typed value")
      box:SetText("junk")
      box:GetScript("OnEscapePressed")(box)
      assert(box:GetText() == "Typed name",
        "Escape must revert to the committed value")

      -- Enter on an unchanged value is not a commit (for the window name it
      -- would freeze an auto-named title as custom); a rejected value puts
      -- the stored one back on screen and as the revert point.
      local inputSets = 0
      inputSpec.set = function(value)
        inputSets = inputSets + 1
        if value ~= "" then inputValue = value end
      end
      box:SetText("Typed name")
      box:GetScript("OnEnterPressed")(box)
      assert(inputSets == 0, "Enter on an unchanged value committed it")
      box:SetText("")
      box:GetScript("OnEnterPressed")(box)
      assert(inputSets == 1 and inputValue == "Typed name")
      assert(box:GetText() == "Typed name" and rawget(box, "skadaDisplayText") == "Typed name",
        "a rejected value must show the stored one again")
      -- A box released to the pool (its page left while it had focus) gives
      -- up the keyboard, and a stray Enter is harmless.
      box:GetScript("OnEditFocusGained")(box)
      Controls.Release(inputFrame)
      assert(rawget(box, "stubFocused") == false and not rawget(box, "skadaHasFocus"),
        "a released input kept keyboard focus")
      box:GetScript("OnEnterPressed")(box)

      -- Click-time dimming: a control painted enabled whose spec has since
      -- become disabled (changed outside the dialog) refuses the click and
      -- repaints itself dimmed.
      local gate = false
      local gatedValue = false
      local gatedButton = Controls.Render(anchor, {
        type = "toggle", name = "Gated toggle",
        disabled = function() return gate end,
        get = function() return gatedValue end,
        set = function(value) gatedValue = value end,
      }, 170)
      assert(gatedButton.disabled == false)
      gate = true
      gatedButton.OnClick(gatedButton)
      assert(gatedValue == false, "a control whose spec is now disabled still committed")
      assert(gatedButton.disabled == true and gatedButton.alpha < 1,
        "a refused click must repaint the stale dimming")
      gate = false
      gatedButton.OnClick(gatedButton)
      assert(gatedValue == true, "a control whose spec is enabled again refused the click")

      -- A commit-on-release slider (Saved fights deletes fights) writes only
      -- where the drag ends, not every value it passes.
      local releasedValue, releasedSets = 10, 0
      local releaseFrame = Controls.Render(anchor, {
        type = "range", name = "Release range", min = 1, max = 50, step = 1,
        commitOnRelease = true,
        get = function() return releasedValue end,
        set = function(value) releasedValue = value; releasedSets = releasedSets + 1 end,
      }, 170)
      local releaseSlider = releaseFrame.slider
      releaseSlider:GetScript("OnValueChanged")(releaseSlider, 4)
      releaseSlider:GetScript("OnValueChanged")(releaseSlider, 10)
      assert(releasedSets == 0 and releaseFrame.valueText:GetText() == "10",
        "a commit-on-release drag wrote before release")
      releaseSlider:GetScript("OnValueChanged")(releaseSlider, 12)
      releaseSlider:GetScript("OnMouseUp")(releaseSlider)
      assert(releasedSets == 1 and releasedValue == 12, "release did not commit the final value")

      -- Rebuilding the same page mid-drag drops the held value; leaving
      -- the page mid-drag still lands it.
      -- The client fires the slider's OnHide inside the frame's Hide, while
      -- the spec is still bound; the stub does not, so do it here.
      local releaseSpec = releaseFrame.spec
      local stubHide = releaseFrame.Hide
      releaseFrame.Hide = function(self)
        releaseSlider:GetScript("OnHide")(releaseSlider)
        stubHide(self)
      end
      releaseSlider:GetScript("OnValueChanged")(releaseSlider, 3)
      Controls.Release(releaseFrame, true)
      assert(releasedSets == 1 and releasedValue == 12,
        "a same-page rebuild committed the value a drag was passing")
      releaseFrame = Controls.Render(anchor, releaseSpec, 170)
      releaseSlider = releaseFrame.slider
      releaseSlider:GetScript("OnValueChanged")(releaseSlider, 20)
      Controls.Release(releaseFrame, false)
      assert(releasedSets == 2 and releasedValue == 20, "leaving the page mid-drag lost the value")
      releaseFrame.Hide = stubHide
    ''')

    # ------------------------------------------------------------------
    # The dialog against changes made outside it, and its own rebuilds.
    # ------------------------------------------------------------------
    ctx.run(r'''
      local Dialog = Skada.OptionsDialog
      local Schema = Skada.OptionsSchema
      local primary = Skada.UI:GetPrimary()
      Dialog:Open(Schema.WindowPageKey(primary))
      local dialog = Dialog.Frame()
      local function findControl(key)
        local controlIndex, control
        for controlIndex = 1, table.getn(dialog.controls) do
          control = dialog.controls[controlIndex]
          if control.spec.name == key then return control end
        end
      end

      -- Rebuilding the page on screen binds every option to the frame it
      -- had (a slider held mid-drag keeps writing its own setting).
      local widthBefore, opacityBefore = findControl("Width"), findControl("Window opacity")
      Dialog:Refresh()
      assert(findControl("Width") == widthBefore and findControl("Window opacity") == opacityBefore,
        "a same-page rebuild shuffled controls between options")

      -- A name being typed survives a same-page rebuild (a window renaming
      -- itself on a combat switch) with its text and focus.
      local nameControl = findControl("Window name")
      local box = nameControl.box
      rawset(box, "left", 100)
      Skada.OptionsControls.PumpInputDisplay()
      box:GetScript("OnEditFocusGained")(box)
      box:SetText("Tank meter")
      Dialog:Refresh()
      Skada.OptionsControls.PumpInputDisplay()
      assert(findControl("Window name") == nameControl and box:GetText() == "Tank meter"
        and rawget(box, "skadaHasFocus"), "a same-page rebuild wiped the name being typed")
      box:GetScript("OnEscapePressed")(box)
      assert(box:GetText() == primary.db.name, "Escape must revert to the stored name")

      -- Batching: several redraw requests inside one batch rebuild once.
      local rebuilds = 0
      local realRebuild = Dialog.RebuildPane
      Dialog.RebuildPane = function(self) rebuilds = rebuilds + 1 return realRebuild(self) end
      Skada.Options:BeginBatch()
      Dialog:Refresh()
      Dialog:Refresh()
      Dialog:RepaintControls()
      assert(rebuilds == 0, "a batched refresh redrew before the batch ended")
      Skada.Options:EndBatch()
      assert(rebuilds == 1, "a batch redrew " .. rebuilds .. " times instead of once")
      Dialog.RebuildPane = realRebuild

      -- A change made outside the dialog (the meter's own mode menu, or a
      -- combat switch) repaints the open page's values and dimming.
      local modeBefore = primary.db.mode
      local segment = findControl("Segment")
      assert(segment.disabled == false, "segment must be live on a non-live mode")
      Skada.Modes:Set("threat", primary)
      primary.manager:NotifyWindowChanged(primary)
      assert(segment.disabled == true and findControl("Mode").valueText:GetText() == "Threat",
        "an outside mode change left the open page stale")
      Skada.Modes:Set(modeBefore, primary)
      primary.manager:NotifyWindowChanged(primary)
      assert(segment.disabled == false, "an outside mode change left the segment dimmed")
      Dialog:Close()
    ''')

    # ------------------------------------------------------------------
    # Schema: the data contract every renderer consumes.
    # ------------------------------------------------------------------
    ctx.run(r'''
      local function countKeys(t)
        local count = 0
        local key
        for key in pairs(t) do count = count + 1 end
        return count
      end

      local options = Skada.OptionsSchema:BuildOptions()
      assert(options.type == "group" and options.name == "Skada")
      assert(options.args.general and options.args.general.type == "group")
      assert(options.args.windows and options.args.windows.type == "group")

      assert(options.args.appearance and options.args.appearance.type == "group")
      assert(options.args.data and options.args.data.type == "group")
      assert(options.args.general.order == 1 and options.args.appearance.order == 2
        and options.args.data.order == 3 and options.args.windows.order == 4,
        "pages must keep their sidebar order")
      assert(options.args.general.desc and options.args.appearance.desc and options.args.data.desc,
        "every page carries the one-line description its title row shows")

      local generalArgs = options.args.general.args
      local appearanceArgs = options.args.appearance.args
      local dataArgs = options.args.data.args
      local function assertKeys(args, expected, pageName)
        assert(countKeys(args) == countKeys(expected),
          pageName .. " must hold exactly its rows, got " .. countKeys(args))
        local key
        for key in pairs(expected) do
          assert(args[key], "setting is missing from " .. pageName .. ": " .. key)
        end
        for key in pairs(args) do
          assert(expected[key], "unexpected row on " .. pageName .. ": " .. tostring(key))
        end
      end
      assertKeys(generalArgs, {
        trackingHeader = true, mergePets = true, trackAll = true, useNampower = true,
        clientHeader = true, minimap = true, combatLogging = true,
        snapHeader = true, snapDistance = true, snapGap = true,
      }, "General")
      assertKeys(appearanceArgs, {
        windowsHeader = true, windowBorderStyle = true, windowBorderColor = true, classColorMenus = true,
        barsHeader = true, barTexture = true, fontName = true, numberFormat = true,
        showClassIcons = true, barBorder = true, barBorderColor = true,
        colorsHeader = true, classColors = true, barColor = true, spellColors = true,
        highlightSelf = true, highlightSelfColor = true,
      }, "Appearance")
      assertKeys(dataArgs, {
        historyHeader = true, maxSegments = true, onlyBossFights = true, resetData = true,
        policyHeader = true, resetOnEnterInstance = true, resetOnJoinGroup = true,
        resetOnLeaveGroup = true, policyNote = true,
      }, "Data")
      assert(generalArgs.mergePets.type == "toggle")
      assert(dataArgs.maxSegments.type == "range")
      assert(appearanceArgs.fontName.type == "select")
      assert(appearanceArgs.windowBorderColor.type == "color")
      assert(dataArgs.resetData.type == "execute")
      assert(generalArgs.trackingHeader.type == "header")
      assert(dataArgs.policyNote.type == "note")

      -- Dependents declare when they do not apply; the schema is the only
      -- place that knows the rule.
      local Controls = Skada.OptionsControls
      Skada.db.profile.barBorder = false
      assert(Controls.IsDisabled(appearanceArgs.barBorderColor) == true,
        "bar border color must be disabled while bar borders are off")
      Skada.db.profile.barBorder = true
      assert(Controls.IsDisabled(appearanceArgs.barBorderColor) == false)
      Skada.db.profile.barBorder = false
      Skada.db.profile.highlightSelf = false
      assert(Controls.IsDisabled(appearanceArgs.highlightSelfColor) == true)
      appearanceArgs.windowBorderStyle.set("none")
      assert(Controls.IsDisabled(appearanceArgs.windowBorderColor) == true,
        "border color must be disabled with no border")
      appearanceArgs.windowBorderStyle.set("solid")
      assert(Controls.IsDisabled(appearanceArgs.windowBorderColor) == false)
      assert(Controls.IsDisabled(generalArgs.useNampower) == true,
        "the Nampower toggle must be disabled while Nampower is absent")

      -- every leaf must carry order + a get (headers/execute excepted) so it
      -- renders deterministically and reads real state.
      local pageArgs
      for _, pageArgs in pairs({ generalArgs, appearanceArgs, dataArgs }) do
        for key, spec in pairs(pageArgs) do
          assert(spec.order, "row " .. key .. " has no order")
          if spec.type ~= "header" and spec.type ~= "execute" and spec.type ~= "note" then
            assert(spec.get, "row " .. key .. " has no get")
          end
        end
      end

      local windowsArgs = options.args.windows.args
      assert(windowsArgs.newWindow == nil,
        "the Windows node must carry no rows of its own; the sidebar plus creates windows")

      -- Bar font dropdown: values/sorting are keyed and ordered off the same
      -- ordered choice list every dropdown in this schema shares.
      local fontRow = appearanceArgs.fontName
      local fontValues = fontRow.values()
      local fontSorting = fontRow.sorting()
      assert(fontValues["Fonts\\FRIZQT__.TTF"] == "Friz Quadrata")
      assert(fontSorting[1] == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf",
        "font choices lost their intended display order")
      Skada.db.profile.fontName = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf"
      fontRow.set("Fonts\\FRIZQT__.TTF")
      assert(Skada.db.profile.fontName == "Fonts\\FRIZQT__.TTF")
      fontRow.set("Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")
      assert(Skada.db.profile.fontName == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")
      assert(fontRow.get() == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")

      local checkRow = generalArgs.mergePets
      local before = Skada.db.profile.mergePets
      local flipped = not before
      checkRow.set(flipped)
      assert(Skada.db.profile.mergePets == flipped)
      checkRow.set(before)
      assert(checkRow.get() == before)

      local primary = Skada.UI:GetPrimary()
      local second = Skada.UI:CreateNew("Settings meter")
      Skada.Options:CycleWindow(1)
      assert(Skada.Options.selectedWindow == second)
      assert(Skada.UI:GetActive() == second)
      Skada.Options:CycleWindow(1)
      assert(Skada.Options.selectedWindow == primary)
      Skada.Options:CycleWindow(-1)
      assert(Skada.Options.selectedWindow == second)

      second.db.width = 321
      local windowArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      assert(windowArgs.width.min == Skada.UIStyle.MIN_WINDOW_WIDTH and windowArgs.width.max == 600)
      assert(windowArgs.width.get() == 321)
      windowArgs.width.set(205)
      assert(second.db.width == 205 and second.db.width >= Skada.UIStyle.MIN_WINDOW_WIDTH,
        second.db.width)
      -- Window settings live on the window only: the profile keeps no copy,
      -- not even of the first window's.
      local primaryArgs = Skada.OptionsSchema:BuildWindowArgs(primary)
      primaryArgs.width.set(primary.db.width + 5)
      assert(Skada.db.profile.width == nil,
        "a window setting was copied into the profile")
      primaryArgs.width.set(primary.db.width - 5)

      local fontSizeArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      assert(fontSizeArgs.fontSize.min == 8 and fontSizeArgs.fontSize.max == 22)
      fontSizeArgs.fontSize.set(15)
      assert(second.db.fontSize == 15, second.db.fontSize)

      -- barAlpha/windowOpacity are percent ranges: 0..1 values displayed as
      -- 0%..100%, no custom formatter needed.
      assert(windowArgs.barAlpha.isPercent and windowArgs.barAlpha.min == 0 and windowArgs.barAlpha.max == 1)
      assert(windowArgs.windowOpacity.isPercent)

      windowArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      assert(windowArgs.width and windowArgs.name and windowArgs.mode and windowArgs.segment
        and windowArgs.combatMode and not windowArgs.returnAfterCombat
        and windowArgs.deleteWindow, "window args missing expected rows")
      assert(not windowArgs.windowBorderStyle and not windowArgs.windowBorderColor,
        "global border controls leaked onto a window's args")
      local modeBefore = second.db.mode
      assert(countKeys(windowArgs) == 21, "window args must hold every per-window row")
      assert(windowArgs.deleteWindow.placement == "title", "delete belongs to the title row")
      assert(not windowArgs.snapDistance and not windowArgs.snapGap,
        "snap distance and gap moved to General")
      assert(Skada.OptionsControls.IsDisabled(windowArgs.snapSize) == not second.db.snap)
      second.db.mode = "threat"
      assert(Skada.OptionsControls.IsDisabled(windowArgs.segment) == true,
        "the segment must be disabled on a live mode")
      second.db.mode = modeBefore

      windowArgs.mode.set("healing")
      assert(second.db.mode == "healing", second.db.mode)
      windowArgs.mode.set("threat")
      assert(second.db.mode == "threat" and second.db.segment == "current",
        "live mode did not coerce the segment")
      windowArgs.mode.set(modeBefore)
      assert(second.db.mode == modeBefore)

      -- an auto-named window follows its mode's name; a hand-set name stays,
      -- and the change must funnel into Options:Refresh so an open dialog
      -- rebuilds (sidebar relabels itself).
      local Dialog = Skada.OptionsDialog
      local refreshed = false
      local savedRefresh = Dialog.Refresh
      Dialog.Refresh = function(self) refreshed = true end

      local auto = Skada.UI:CreateNew()
      assert(auto.db.name == Skada.Modes:Get(auto.db.mode).title and not auto.db.nameIsCustom,
        "a new window should be auto-named from its mode")
      local autoArgs = Skada.OptionsSchema:BuildWindowArgs(auto)
      refreshed = false
      autoArgs.mode.set("healing")
      assert(auto.db.mode == "healing" and auto.db.name == "Healing" and not auto.db.nameIsCustom,
        "switching mode did not rename the auto-named window")
      assert(refreshed, "renaming via mode switch did not refresh the open dialog")
      assert(Skada.OptionsSchema:BuildWindowsArgs()["window_" .. auto.db.id].name == "Healing",
        "a freshly-built windows group did not pick up the mode-derived name")

      refreshed = false
      autoArgs.name.set("My meter")
      assert(auto.db.name == "My meter" and auto.db.nameIsCustom,
        "manual rename did not mark the window as custom-named")
      assert(refreshed, "renaming did not refresh the open dialog")
      auto:Refresh()
      assert(auto.title.textValue == "My meter",
        "refresh did not paint a custom window title")
      autoArgs.mode.set("threat")
      assert(auto.db.name == "My meter", "mode switch clobbered a custom window name")
      auto:Refresh()
      assert(auto.title.textValue == "My meter",
        "dynamic live-mode title replaced a custom window title")
      assert(Skada.UI:DeleteWindow(auto), "temporary window cleanup failed")
      Dialog.Refresh = savedRefresh

      windowArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      windowArgs.segment.set(1)
      assert(second.db.segment == 1, second.db.segment)
      windowArgs.segment.set("total")
      assert(second.db.segment == "total", second.db.segment)
      windowArgs.segment.set("current")
      assert(second.db.segment == "current", second.db.segment)

      -- combat mode switching an in-combat window applies immediately
      local combatBefore = second.db.combatMode
      windowArgs.combatMode.set("threat")
      assert(second.db.combatMode == "threat", second.db.combatMode)
      windowArgs.combatMode.set("")
      assert(second.db.combatMode == "", second.db.combatMode)

      windowArgs.name.set("Renamed meter")
      assert(second.db.name == "Renamed meter", second.db.name)

      local wasVisible = second.db.visible
      windowArgs.visible.set(false)
      assert(second.db.visible == false and not second.frame:IsShown(),
        "visibility toggle did not hide the window")
      windowArgs.visible.set(true)
      assert(second.db.visible == true and second.frame:IsShown(),
        "visibility toggle did not reshow the window")
      if not wasVisible then windowArgs.visible.set(false) end

      local hideBefore = second.db.hideTitle
      windowArgs.hideTitle.set(not hideBefore)
      assert(second.db.hideTitle == not hideBefore and second.layoutDirty,
        "hide-title toggle did not mark the window layout dirty")
      windowArgs.hideTitle.set(hideBefore)

      local sizeBefore = second.db.snapSize
      windowArgs.snapSize.set(not sizeBefore)
      assert(second.db.snapSize == not sizeBefore)
      windowArgs.snapSize.set(sizeBefore)

      -- Snap distance and gap are edited once, on General, and written to
      -- every window; the getter reads the primary.
      local snapArgs = Skada.OptionsSchema:BuildOptions().args.general.args
      snapArgs.snapDistance.set(7)
      assert(second.db.snapDistance == 7 and primary.db.snapDistance == 7,
        "General snap distance must reach every window")
      assert(snapArgs.snapDistance.get() == 7)
      snapArgs.snapGap.set(3)
      assert(second.db.snapGap == 3 and primary.db.snapGap == 3)
      snapArgs.snapDistance.set(12)
      snapArgs.snapGap.set(0)
    ''')

    # ------------------------------------------------------------------
    # Sidebar: the plus button, selection, delete flow.
    # ------------------------------------------------------------------
    ctx.run(r'''
      local Dialog = Skada.OptionsDialog
      local primary = Skada.UI:GetPrimary()
      local second
      local windowIndex, window
      for windowIndex = 1, table.getn(Skada.UI.windows) do
        window = Skada.UI.windows[windowIndex]
        if window ~= primary then second = window break end
      end
      assert(second, "the suite's earlier window is missing")

      Skada.Options:Open()
      local dialog = Dialog.Frame()
      local rows = dialog.sidebar.rows
      assert(Dialog.selectedGroup == "window_" .. tostring(second.db.id),
        "a plain open must keep the previously selected group")

      -- The plus button creates a window and jumps to its pane; the rebuild
      -- that creation triggers must keep the header, the plus, and the new
      -- row (every sidebar row is rebuilt from scratch on refresh).
      local windowsBefore = table.getn(Skada.UI.windows)
      local plus = rows[4].plusButton
      plus.OnClick(plus)
      local third = Skada.Options.selectedWindow
      assert(third and third ~= second and third ~= primary, "new window was not created and selected")
      assert(third.db.name == Skada.Modes:Get(third.db.mode).title,
        "unnamed window must default to its tracked mode's title")
      assert(Skada.UI.byID[third.db.id] == third, "created window missing from the registry")
      assert(Dialog.selectedGroup == "window_" .. tostring(third.db.id),
        "creating a window did not open its pane")
      assert(table.getn(dialog.controls) == 21, "the new window's pane did not build")
      rows = dialog.sidebar.rows
      assert(table.getn(rows) == 4 + table.getn(Skada.UI.windows),
        "sidebar did not relist the windows after the creation rebuild")
      assert(rows[4].plusButton and rawget(rows[4].plusButton, "normalTexture") == "Interface\\Buttons\\UI-PlusButton-UP",
        "the Windows row lost its plus after the rebuild")
      assert(rows[table.getn(rows)].text.textValue == third.db.name,
        "the new window is not listed under the Windows header")
      assert(rows[table.getn(rows)].marker:IsShown(),
        "the new window's row must show its marker once selected")
      local windowArgs = Skada.OptionsSchema:BuildWindowsArgs()
      assert(windowArgs["window_" .. third.db.id], "new window missing its own args subgroup")

      -- The window-name input on its pane goes through the display pump: the
      -- box is queued at build, filled only once placed, and commit/refresh
      -- relabel the sidebar row.
      local inputControl
      local controlIndex, control
      for controlIndex = 1, table.getn(dialog.controls) do
        control = dialog.controls[controlIndex]
        if control.spec.type == "input" then inputControl = control break end
      end
      assert(inputControl, "the window pane has no input control")
      local box = inputControl.box
      -- A fresh box was never SetText; a pooled one is blanked on rebind.
      assert(box:GetText() == nil or box:GetText() == "", "the window-name box must start unfilled")
      rawset(box, "left", 100)
      Skada.OptionsControls.PumpInputDisplay()
      assert(box:GetText() == third.db.name,
        "the pump did not display the window name, got " .. tostring(box:GetText()))
      box:SetText("Third meter")
      box:GetScript("OnEnterPressed")(box)
      assert(third.db.name == "Third meter" and third.db.nameIsCustom,
        "Enter did not commit the renamed window")
      Skada.OptionsDialog:RebuildSidebar()
      assert(dialog.sidebar.rows[table.getn(dialog.sidebar.rows)].text.textValue == "Third meter",
        "the sidebar row did not relabel after the rename")

      -- Delete: confirmation first (StaticPopup lives at DIALOG, above this
      -- HIGH dialog), fallback of the selection after accept.
      Skada.Options:SelectWindow(third)
      assert(dialog.titleAction:IsShown() and dialog.titleAction.spec.name == "Delete window",
        "the selected window's page must offer the title-row delete button")
      dialog.titleAction.OnClick(dialog.titleAction)
      assert(TestLastPopup == "SKADA_DELETE_WINDOW", tostring(TestLastPopup))
      assert(Skada.UI.byID[third.db.id] == third, "delete popup must not delete before accept")
      assert(StaticPopupDialogs.SKADA_DELETE_WINDOW, "delete dialog not registered")
      StaticPopupDialogs.SKADA_DELETE_WINDOW.OnAccept()
      assert(Skada.UI.byID[third.db.id] == nil, "accepted delete did not remove the window")
      assert(Skada.Options.selectedWindow == primary, "panel did not fall back after delete")
      local windowsArgs = Skada.OptionsSchema:BuildWindowsArgs()
      assert(not windowsArgs["window_" .. third.db.id], "deleted window kept its args subgroup")

      -- regression: a window created after a delete must stay visible to
      -- getn-based loops. The client is Lua 5.0, whose table.getn trusts the
      -- size cache table.remove maintains; a manual `windows[getn + 1] = v`
      -- append after a delete left the new window rendering on screen while
      -- every getn loop (including this one, over Skada.UI.windows) could
      -- not see it.
      local fourth = Skada.UI:CreateNew()
      assert(fourth and Skada.UI.byID[fourth.db.id] == fourth,
        "window created after a delete missed the registry")
      assert(table.getn(Skada.db.profile.windows) == 3,
        table.getn(Skada.db.profile.windows))
      windowsArgs = Skada.OptionsSchema:BuildWindowsArgs()
      assert(windowsArgs["window_" .. fourth.db.id], "window created after a delete missed its args subgroup")
      Skada.UI:DeleteWindow(fourth)
    ''')

    ctx.run(r'''
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

      local pages = Skada.OptionsSchema:BuildOptions().args
      local generalArgs, appearanceArgs, dataArgs = pages.general.args, pages.appearance.args, pages.data.args
      appearanceArgs.numberFormat.set("compact1")
      assert(profile.numberFormat == "compact1", profile.numberFormat)
      appearanceArgs.numberFormat.set("compact")

      profile.maxSegments = 10
      dataArgs.maxSegments.set(7)
      assert(profile.maxSegments == 7, profile.maxSegments)
      assert(table.getn(Skada.Data.history) <= profile.maxSegments,
        "history was not trimmed to the new value")

      -- Earlier suites leave the client flagged in combat, and a reset taken
      -- mid-fight reopens a segment; the zone policies below only apply out
      -- of combat, so take the whole block out of combat first.
      Skada.Data.clientInCombat = false
      Skada.Data.active = false
      table.insert(Skada.Data.history, Skada.Data.current)
      dataArgs.resetData.func()
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
      StaticPopupDialogs.SKADA_RESET_POLICY.OnAccept()
      assert(table.getn(Skada.Data.history) == 1, "an accepted reset popup cleared data mid-fight")
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

      local windowBorderRow = appearanceArgs.windowBorderStyle
      local borderValues = windowBorderRow.values()
      assert(borderValues.solid and borderValues.none)
      windowBorderRow.set("solid")
      assert(Skada.db.profile.windowBorderStyle == "solid",
        "solid window border choice was not saved")
      windowBorderRow.set("none")
      assert(Skada.db.profile.windowBorderStyle == "none" and windowBorderRow.get() == "none",
        "borderless choice was not saved")
      windowBorderRow.set("solid")
      assert(Skada.db.profile.windowBorderStyle == "solid")

      local miniRow = generalArgs.minimap
      miniRow.set(false)
      assert(Skada.db.profile.minimap.show == false)
      assert(not Skada.Options.minimapButton:IsShown())
      miniRow.set(true)
      assert(Skada.db.profile.minimap.show == true)
      assert(Skada.Options.minimapButton:IsShown())

      -- Left-click toggles every window together, not just the active one:
      -- all hide while any is shown, all show otherwise, and each window's
      -- own visible flag follows.
      local button = Skada.Options.minimapButton
      local extra = Skada.UI:CreateNew("Minimap toggle meter")
      local primary = Skada.UI:GetPrimary()
      assert(primary.db.visible and extra.db.visible)
      button.OnClick(button, "LeftButton")
      assert(not primary.db.visible and not extra.db.visible
        and not primary.frame:IsShown() and not extra.frame:IsShown(),
        "left-click must hide every window")
      extra.db.visible = true
      extra.frame:Show()
      button.OnClick(button, "LeftButton")
      assert(not primary.db.visible and not extra.db.visible,
        "with any window shown, left-click must hide all")
      button.OnClick(button, "LeftButton")
      assert(primary.db.visible and extra.db.visible
        and primary.frame:IsShown() and extra.frame:IsShown(),
        "with every window hidden, left-click must show all")
      assert(Skada.UI:DeleteWindow(extra))
    ''')

    # ------------------------------------------------------------------
    # Lifecycle: close is synchronous; reopen shows everything again.
    # ------------------------------------------------------------------
    ctx.run(r'''
      local dialog = Skada.OptionsDialog.Frame()
      local configuredBorder = Skada.db.profile.windowBorderColor
      local primary = Skada.UI:GetPrimary()
      local borderEdges = rawget(primary.frame, "skadaBorderEdges")

      Skada.Options:Close()
      assert(not dialog:IsShown(), "Close did not hide the dialog")
      assert(Skada.UI.visualActive == nil, "closing settings kept the visual selection")
      assert(borderEdges[1].vertexR == configuredBorder[1],
        "closing settings changed the configured border color")

      -- Synchronous reopen: values and structure come back immediately, no
      -- open/close dance.
      Skada.Options:Open()
      dialog = Skada.OptionsDialog.Frame()
      assert(dialog:IsShown(), "Open did not reshow the dialog")
      assert(table.getn(dialog.controls) == 11, "reopen did not rebuild the pane")
      assert(table.getn(dialog.sidebar.rows) == 4 + table.getn(Skada.UI.windows),
        "reopen did not rebuild the sidebar")
      assert(borderEdges[1].vertexR == configuredBorder[1],
        "reopening settings changed the configured border color")
      Skada.Options:Toggle()
      assert(not dialog:IsShown(), "Toggle did not close an open dialog")

      Skada.UI:SetActive(primary)
      local second
      local windowIndex, window
      for windowIndex = 1, table.getn(Skada.UI.windows) do
        window = Skada.UI.windows[windowIndex]
        if window ~= primary then second = window break end
      end
      assert(Skada.UI:DeleteWindow(second))
    ''')
