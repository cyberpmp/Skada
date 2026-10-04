"""Suite: isolation - Skada keeps to its own UI surfaces and never touches
the Blizzard-shared GameTooltip that other addons depend on. The transmog-
rify service, for one, feeds item hyperlinks into the shared tooltip via
SetHyperlink to force the server to fetch item data, then builds its
per-slot available-item lists from whatever landed in the client's item
cache; if Skada owns or hides that frame while it happens, the fetch is
swallowed and some slots stop listing their items. These tests lock the
guarantees down."""

from harness import Context


def run(ctx: Context):
    # The private tooltip exists and is not the shared Blizzard GameTooltip.
    # Its shared-frame traffic is instrumented before anything is touched.
    ctx.run(r'''
      local tooltip = Skada.Common.GetTooltip()
      assert(tooltip ~= GameTooltip,
        "Skada must not render on the shared GameTooltip")
      assert(tooltip.name == "SkadaTooltip")
      local touches = { owner = 0, show = 0, hide = 0 }
      GameTooltip.__isolation = touches
      GameTooltip.SetOwner = function(self) touches.owner = touches.owner + 1 end
      GameTooltip.Show = function(self) touches.show = touches.show + 1 end
      GameTooltip.Hide = function(self) touches.hide = touches.hide + 1 end
    ''')

    # Repaint the meter, fire the row scripts, hover an AttachTooltip button
    # and the window header: all tooltip traffic stays on the private frame.
    ctx.run(r'''
      local meter = Skada.UI:GetPrimary()
      local touches = GameTooltip.__isolation
      local rowCount, row = table.getn(meter.rows), nil
      local rowIndex
      for rowIndex = 1, rowCount do
        if meter.rows[rowIndex].entry then row = meter.rows[rowIndex] end
      end
      assert(row and row.OnEnter and row.OnLeave, "meter rows were not scripted")
      meter:Refresh()
      row.OnEnter(row)
      assert(touches.owner == 0 and touches.show == 0,
        "row entry tooltip owned or showed the shared GameTooltip")
      row.OnLeave(row)
      assert(touches.hide == 0, "row leave hid the shared GameTooltip")

      local button = CreateFrame("Button", nil, UIParent)
      Skada.Common.AttachTooltip(button, "Probe", "Probe body")
      local tooltip = Skada.Common.GetTooltip()
      local seen = {}
      local savedAddLine = tooltip.AddLine
      tooltip.AddLine = function(self, text, r, g, b, wrap)
        seen[table.getn(seen) + 1] = tostring(text)
        if savedAddLine then savedAddLine(self, text, r, g, b, wrap) end
      end
      button.OnEnter(button)
      assert(seen[1] == "Probe" and seen[2] == "Probe body",
        "AttachTooltip did not draw on the private tooltip frame")
      button.OnLeave(button)
      tooltip.AddLine = savedAddLine
      touches.owner, touches.show, touches.hide = 0, 0, 0

      local header = rawget(meter, "header")
      if header and header.OnEnter then
        header.OnEnter(header)
        header.OnLeave(header)
        assert(touches.owner == 0 and touches.show == 0 and touches.hide == 0,
          "header hover touched the shared GameTooltip")
      end

      -- A full repaint with a row still hovered keeps the shared frame clear.
      row.OnEnter(row)
      meter:Refresh()
      row.OnLeave(row)
      assert(touches.owner == 0 and touches.show == 0 and touches.hide == 0,
        "repaint touched the shared GameTooltip")
    ''')

    # The global string.split / strsplit shim follows the standard split
    # contract: empty fields kept, delimiter characters matched literally,
    # optional pieces cap with the remainder in the final field. Skada never
    # calls this itself; other addon code does, and the previous replacement
    # dropped empty fields and collapsed delimiter runs ("a::b" returned
    # only "a" and "b"), which broke parsers that count their fields.
    ctx.run(r'''
      local chunk, err = loadstring([=[
        local function collect(...)
          local out = {}
          for i = 1, select("#", ...) do out[i] = tostring(select(i, ...)) end
          return table.concat(out, "|")
        end
        assert(collect(string.split(":", "a::b")) == "a||b", "empty fields were dropped")
        assert(collect(strsplit(",", ",start")) == "|start")
        assert(collect(strsplit(",;", "a,b;c")) == "a|b|c")
        assert(collect(strsplit(":|", "a|b:c")) == "a|b|c")
        -- pattern metacharacters in the delimiter list must split literally
        assert(collect(strsplit("%a", "1%2")) == "1|2")
        assert(collect(string.split("-", "a-b")) == "a|b")
        -- non-string values are read as text, not errors
        assert(collect(strsplit(" ", 123)) == "123")
        -- pieces cap: remainder stays in the final field
        assert(collect(strsplit(",", "a,b,c", 2)) == "a|b,c")
        assert(collect(strsplit(",", "a,b,c", 1)) == "a,b,c")
        assert(collect(strsplit(",", "a,b,c", 3)) == "a|b|c")
        assert(collect(strsplit(",", "a,b,c", 10)) == "a|b|c")
        -- degenerate inputs
        assert(collect(strsplit(",", "")) == "")
        assert(collect(strsplit(":", "abc")) == "abc")
        assert(select("#", strsplit(":", nil)) == 0)
      ]=])
      assert(err == nil, tostring(err))
      chunk()
    ''')