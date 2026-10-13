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
