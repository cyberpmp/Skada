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
      assert(framesChecked > 30, "dialog subtree walk found only " .. framesChecked .. " frames")

      -- Chrome: the default UI's own dialog-box frame, untinted (no black
      -- wash, no drop shadow), tooltip-bordered inset panes, the header
      -- ribbon's gold title, a red panel Close button and the round X.
      local Style = Skada.UIStyle
      assert(dialog.backdrop == Style.DIALOG_BACKDROP and dialog.backdropR == 1
        and dialog.backdropA == 1, "dialog root must wear the untinted dialog-box frame")
      assert(rawget(dialog, "skadaShadow") == nil, "classic chrome draws no drop shadow")
      assert(dialog.dialogTitle.textValue == "Skada" and dialog.dialogTitle.textR == Style.GOLD_R,
        "dialog must carry the gold header-ribbon title")
      assert(dialog.sidebar.backdrop == Style.PANE_BACKDROP
        and dialog.pane.backdrop == Style.PANE_BACKDROP,
        "sidebar and pane must be tooltip-bordered insets")
      assert(dialog.closeButton and dialog.closeButton.frameType == "Button"
        and dialog.closeButton.textValue == "Close",
        "dialog must carry a panel Close button")
      assert(dialog.closeX and rawget(dialog.closeX, "normalTexture") == Style.CLOSE_BUTTON_TEXTURE,
        "dialog must carry the round panel X")

      -- Sidebar: General row first, then the Windows header (a plain Frame,
      -- so its label takes no clicks) with its plus button, then one row per
      -- meter window.
      local rows = dialog.sidebar.rows
      assert(table.getn(rows) == 2 + table.getn(Skada.UI.windows),
        "sidebar must hold General + the Windows header + one row per window, got "
        .. table.getn(rows))
      assert(rows[1].text.textValue == "General", "first sidebar row must be General")
      assert(rows[1].frameType == "Button", "the General row must be clickable")
      assert(rows[1].marker:IsShown(), "the selected group's row must show its marker")
      local headerRow = rows[2]
      assert(headerRow.text.textValue == "Windows", "second sidebar row must be the Windows header")
      assert(headerRow.frameType ~= "Button", "the Windows header must not take clicks")
      local plus = headerRow.plusButton
      assert(plus and rawget(plus, "normalTexture") == "Interface\\Buttons\\UI-PlusButton-UP",
        "the Windows header must carry a plus button")
      local windowRowIndex
      for windowRowIndex = 3, table.getn(rows) do
        assert(rows[windowRowIndex].frameType == "Button", "window rows must be clickable")
        -- Unselected window rows read in white; the selected row (General
        -- here) lights the quest-log highlight and turns gold.
        assert(not rows[windowRowIndex].marker:IsShown(), "unselected rows must not light up")
        assert(rows[windowRowIndex].text.textR == 1 and rows[windowRowIndex].text.textG == 1,
          "unselected window rows must read in white")
      end
      assert(rows[1].marker.texture == Style.ROW_HIGHLIGHT_TEXTURE,
        "the selection marker must be the quest-log highlight")
      assert(rows[1].text.textR == Style.GOLD_R and rows[1].text.textG == Style.GOLD_G,
        "the General row must read in gold")

      -- Pane: the General group renders every one of its rows as a control,
      -- laid out arithmetically inside the scroll child.
      assert(table.getn(dialog.controls) == 29,
        "General pane did not build every control: " .. table.getn(dialog.controls))
      assert(dialog.content:GetWidth() == 518,
        "scroll child must carry the arithmetic width, got " .. tostring(dialog.content:GetWidth()))
      assert(dialog.scrollframe:GetName() == "SkadaOptionsScrollFrame",
        "pane scroll frame must be named (its template scrollbar is <name>ScrollBar)")
      assert(dialog.scrollbar == _G.SkadaOptionsScrollFrameScrollBar,
        "the pane scroll frame must use its template's own scrollbar")
      assert(dialog.scrollframe:IsMouseWheelEnabled(),
        "the pane scroll frame must scroll on the mouse wheel")

      -- Every built control must carry a back-reference to its spec, and the
      -- rendered types must match the schema's.
      local controlIndex, control
      local executeSeen = false
      for controlIndex = 1, table.getn(dialog.controls) do
        control = dialog.controls[controlIndex]
        assert(control.spec and control.spec.type, "a pane control lost its spec reference")
        if control.spec.type == "execute" then
          executeSeen = true
          -- The panel button sits inset in its row rather than on the cell's
          -- edge, and a full-width row keeps it at a button's width.
          assert(control.lastPointX == 4 and control.lastPointY < 0,
            "execute button must be placed at its cell inset")
          assert(control:GetWidth() == 200, "full-width execute must keep a button's width")
        end
      end
      assert(executeSeen, "General pane must carry an execute button")

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

      -- Navigating to a window's pane builds its 24 rows; the subtree
      -- layering must hold after the rebuild too.
      Dialog:Open("window_" .. tostring(primary.db.id))
      assert(table.getn(dialog.controls) == 24,
        "window pane did not build every control: " .. table.getn(dialog.controls))
      checkSubtree(dialog, 0)
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
      local inputSeen, rangeSeen = false, false
      for controlIndex = 1, table.getn(dialog.controls) do
        control = dialog.controls[controlIndex]
        if control.spec.type == "input" then inputSeen = true end
        if control.spec.type == "range" then rangeSeen = true end
      end
      assert(inputSeen and rangeSeen, "window pane is missing its input or range controls")
      Dialog:Open("general")
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
        set = function(info, value) sliderValue = value; sliderSetCount = sliderSetCount + 1 end,
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
        set = function(info, value) percentValue = value end,
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
        set = function(info, value) toggleValue = value end,
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
        set = function(info, value) selectValue = value end,
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
      popup:Hide()

      -- The shared popup must repaint the dropdown that opened it, using
      -- the committed value even when the setter normalizes the selection.
      local otherValue = "a"
      local otherButton = Controls.Render(anchor, {
        type = "select", name = "Other select",
        values = selectSpec.values, sorting = selectSpec.sorting,
        get = function() return otherValue end,
        set = function(info, value) otherValue = value == "c" and "b" or value end,
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
        set = function(info, r, g, b) colorRed, colorGreen, colorBlue = r, g, b end,
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

      -- Executes: the click calls spec.func({}) -- the old Ace3 `info`
      -- argument, kept as the call signature.
      local executed = false
      local executeSpec = {
        type = "execute", name = "Test execute",
        func = function(info) executed = info ~= nil end,
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
        set = function(info, value) inputValue = value end,
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

      local generalArgs = options.args.general.args
      assert(countKeys(generalArgs) == 29, "General must hold every global row")
      local globalKeys = {
        mergePets = true, trackAll = true, combatLogging = true, minimap = true,
        useNampower = true,
        behaviorHeader = true, appearanceHeader = true,
        windowBorderStyle = true, windowBorderColor = true, barTexture = true,
        fontName = true, classColors = true, barColor = true, spellColors = true,
        showClassIcons = true, classColorMenus = true, highlightSelf = true,
        highlightSelfColor = true, barBorder = true, barBorderColor = true,
        dataHeader = true, maxSegments = true, onlyBossFights = true, numberFormat = true,
        resetData = true, policyHeader = true, resetOnEnterInstance = true,
        resetOnJoinGroup = true, resetOnLeaveGroup = true,
      }
      local key
      for key in pairs(globalKeys) do
        assert(generalArgs[key], "global setting is missing from General: " .. key)
      end
      for key in pairs(generalArgs) do
        assert(globalKeys[key], "unexpected row on General: " .. tostring(key))
      end
      assert(generalArgs.mergePets.type == "toggle")
      assert(generalArgs.maxSegments.type == "range")
      assert(generalArgs.fontName.type == "select")
      assert(generalArgs.windowBorderColor.type == "color")
      assert(generalArgs.resetData.type == "execute")
      assert(generalArgs.behaviorHeader.type == "header")

      -- every leaf must carry order + a get (headers/execute excepted) so it
      -- renders deterministically and reads real state.
      for key, spec in pairs(generalArgs) do
        assert(spec.order, "row " .. key .. " has no order")
        if spec.type ~= "header" and spec.type ~= "execute" then
          assert(spec.get, "row " .. key .. " has no get")
        end
      end

      local windowsArgs = options.args.windows.args
      assert(windowsArgs.newWindow == nil,
        "the Windows node must carry no rows of its own; the sidebar plus creates windows")

      -- Bar font dropdown: values/sorting are keyed and ordered off the same
      -- ordered choice list every dropdown in this schema shares.
      local fontRow = generalArgs.fontName
      local fontValues = fontRow.values()
      local fontSorting = fontRow.sorting()
      assert(fontValues["Fonts\\FRIZQT__.TTF"] == "Friz Quadrata")
      assert(fontSorting[1] == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf",
        "font choices lost their intended display order")
      Skada.db.profile.fontName = "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf"
      fontRow.set({}, "Fonts\\FRIZQT__.TTF")
      assert(Skada.db.profile.fontName == "Fonts\\FRIZQT__.TTF")
      fontRow.set({}, "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")
      assert(Skada.db.profile.fontName == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")
      assert(fontRow.get() == "Interface\\AddOns\\Skada\\media\\Accidental Presidency.ttf")

      local checkRow = generalArgs.mergePets
      local before = Skada.db.profile.mergePets
      local flipped = not before
      checkRow.set({}, flipped)
      assert(Skada.db.profile.mergePets == flipped)
      checkRow.set({}, before)
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
      windowArgs.width.set({}, 205)
      assert(second.db.width == 205 and second.db.width >= Skada.UIStyle.MIN_WINDOW_WIDTH,
        second.db.width)
      assert(Skada.db.profile.width ~= 205,
        "secondary window design key leaked into the profile mirror")
      local primaryArgs = Skada.OptionsSchema:BuildWindowArgs(primary)
      primaryArgs.width.set({}, primary.db.width + 5)
      assert(Skada.db.profile.width == primary.db.width,
        "primary window design key was not mirrored into the profile")

      local fontSizeArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      assert(fontSizeArgs.fontSize.min == 8 and fontSizeArgs.fontSize.max == 22)
      fontSizeArgs.fontSize.set({}, 15)
      assert(second.db.fontSize == 15, second.db.fontSize)

      -- barAlpha/windowOpacity are percent ranges: 0..1 values displayed as
      -- 0%..100%, no custom formatter needed.
      assert(windowArgs.barAlpha.isPercent and windowArgs.barAlpha.min == 0 and windowArgs.barAlpha.max == 1)
      assert(windowArgs.windowOpacity.isPercent)

      windowArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      assert(windowArgs.width and windowArgs.name and windowArgs.mode and windowArgs.segment
        and windowArgs.combatMode and windowArgs.returnAfterCombat
        and windowArgs.deleteWindow, "window args missing expected rows")
      assert(not windowArgs.windowBorderStyle and not windowArgs.windowBorderColor,
        "global border controls leaked onto a window's args")
      assert(countKeys(windowArgs) == 24, "window args must hold every per-window row")

      local modeBefore = second.db.mode
      windowArgs.mode.set({}, "healing")
      assert(second.db.mode == "healing", second.db.mode)
      windowArgs.mode.set({}, "threat")
      assert(second.db.mode == "threat" and second.db.segment == "current",
        "live mode did not coerce the segment")
      windowArgs.mode.set({}, modeBefore)
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
      autoArgs.mode.set({}, "healing")
      assert(auto.db.mode == "healing" and auto.db.name == "Healing" and not auto.db.nameIsCustom,
        "switching mode did not rename the auto-named window")
      assert(refreshed, "renaming via mode switch did not refresh the open dialog")
      assert(Skada.OptionsSchema:BuildWindowsArgs()["window_" .. auto.db.id].name == "Healing",
        "a freshly-built windows group did not pick up the mode-derived name")

      refreshed = false
      autoArgs.name.set({}, "My meter")
      assert(auto.db.name == "My meter" and auto.db.nameIsCustom,
        "manual rename did not mark the window as custom-named")
      assert(refreshed, "renaming did not refresh the open dialog")
      auto:Refresh()
      assert(auto.title.textValue == "My meter",
        "refresh did not paint a custom window title")
      autoArgs.mode.set({}, "threat")
      assert(auto.db.name == "My meter", "mode switch clobbered a custom window name")
      auto:Refresh()
      assert(auto.title.textValue == "My meter",
        "dynamic live-mode title replaced a custom window title")
      assert(Skada.UI:DeleteWindow(auto), "temporary window cleanup failed")
      Dialog.Refresh = savedRefresh

      windowArgs = Skada.OptionsSchema:BuildWindowArgs(second)
      windowArgs.segment.set({}, 1)
      assert(second.db.segment == 1, second.db.segment)
      windowArgs.segment.set({}, "total")
      assert(second.db.segment == "total", second.db.segment)
      windowArgs.segment.set({}, "current")
      assert(second.db.segment == "current", second.db.segment)

      -- combat mode switching an in-combat window applies immediately
      local combatBefore = second.db.combatMode
      windowArgs.combatMode.set({}, "threat")
      assert(second.db.combatMode == "threat", second.db.combatMode)
      assert(Skada.db.profile.combatMode == combatBefore,
        "secondary window combat mode leaked into the profile mirror")
      windowArgs.combatMode.set({}, "")
      assert(second.db.combatMode == "", second.db.combatMode)

      windowArgs.name.set({}, "Renamed meter")
      assert(second.db.name == "Renamed meter", second.db.name)

      local wasVisible = second.db.visible
      windowArgs.visible.set({}, false)
      assert(second.db.visible == false and not second.frame:IsShown(),
        "visibility toggle did not hide the window")
      windowArgs.visible.set({}, true)
      assert(second.db.visible == true and second.frame:IsShown(),
        "visibility toggle did not reshow the window")
      if not wasVisible then windowArgs.visible.set({}, false) end

      local hideBefore = second.db.hideTitle
      windowArgs.hideTitle.set({}, not hideBefore)
      assert(second.db.hideTitle == not hideBefore and second.layoutDirty,
        "hide-title toggle did not mark the window layout dirty")
      windowArgs.hideTitle.set({}, hideBefore)

      local racBefore = second.db.returnAfterCombat
      windowArgs.returnAfterCombat.set({}, not racBefore)
      assert(second.db.returnAfterCombat == not racBefore)
      windowArgs.returnAfterCombat.set({}, racBefore)

      local sizeBefore = second.db.snapSize
      windowArgs.snapSize.set({}, not sizeBefore)
      assert(second.db.snapSize == not sizeBefore)
      windowArgs.snapSize.set({}, sizeBefore)

      local snapBefore = Skada.db.profile.snapDistance
      windowArgs.snapDistance.set({}, 12)
      assert(second.db.snapDistance == 12, second.db.snapDistance)
      assert(Skada.db.profile.snapDistance == snapBefore,
        "secondary window snap key leaked into the profile mirror")
      local primarySnapArgs = Skada.OptionsSchema:BuildWindowArgs(primary)
      primarySnapArgs.snapDistance.set({}, 7)
      assert(Skada.db.profile.snapDistance == primary.db.snapDistance,
        "primary window snap key was not mirrored into the profile")
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
      local plus = rows[2].plusButton
      plus.OnClick(plus)
      local third = Skada.Options.selectedWindow
      assert(third and third ~= second and third ~= primary, "new window was not created and selected")
      assert(third.db.name == Skada.Modes:Get(third.db.mode).title,
        "unnamed window must default to its tracked mode's title")
      assert(Skada.UI.byID[third.db.id] == third, "created window missing from the registry")
      assert(Dialog.selectedGroup == "window_" .. tostring(third.db.id),
        "creating a window did not open its pane")
      assert(table.getn(dialog.controls) == 24, "the new window's pane did not build")
      rows = dialog.sidebar.rows
      assert(table.getn(rows) == 2 + table.getn(Skada.UI.windows),
        "sidebar did not relist the windows after the creation rebuild")
      assert(rows[2].plusButton and rawget(rows[2].plusButton, "normalTexture") == "Interface\\Buttons\\UI-PlusButton-UP",
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
      assert(box:GetText() == nil, "the window-name box must start unfilled")
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
      local thirdArgs = Skada.OptionsSchema:BuildWindowArgs(third)
      thirdArgs.deleteWindow.func({})
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

      local generalArgs = Skada.OptionsSchema:BuildOptions().args.general.args
      generalArgs.numberFormat.set({}, "compact1")
      assert(profile.numberFormat == "compact1", profile.numberFormat)
      generalArgs.numberFormat.set({}, "compact")

      profile.maxSegments = 10
      generalArgs.maxSegments.set({}, 7)
      assert(profile.maxSegments == 7, profile.maxSegments)
      assert(table.getn(Skada.Data.history) <= profile.maxSegments,
        "history was not trimmed to the new value")

      table.insert(Skada.Data.history, Skada.Data.current)
      generalArgs.resetData.func({})
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

      local windowBorderRow = generalArgs.windowBorderStyle
      local borderValues = windowBorderRow.values()
      assert(borderValues.solid and borderValues.none)
      windowBorderRow.set({}, "solid")
      assert(Skada.db.profile.windowBorderStyle == "solid" and
        not Skada.db.profile.hideWindowBorder,
        "solid window border choice was not saved")
      windowBorderRow.set({}, "none")
      assert(Skada.db.profile.hideWindowBorder,
        "borderless choice did not preserve the legacy setting")
      windowBorderRow.set({}, "solid")
      assert(Skada.db.profile.windowBorderStyle == "solid" and
        not Skada.db.profile.hideWindowBorder)

      local miniRow = generalArgs.minimap
      miniRow.set({}, false)
      assert(Skada.db.profile.minimap.show == false)
      assert(not Skada.Options.minimapButton:IsShown())
      miniRow.set({}, true)
      assert(Skada.db.profile.minimap.show == true)
      assert(Skada.Options.minimapButton:IsShown())
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
      assert(table.getn(dialog.controls) == 29, "reopen did not rebuild the pane")
      assert(table.getn(dialog.sidebar.rows) == 2 + table.getn(Skada.UI.windows),
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
