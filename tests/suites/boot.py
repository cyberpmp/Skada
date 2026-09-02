"""Suite: boot - load invariants, version, primary window, ticker isolation."""

from harness import Context


def run(ctx: Context):
    skada = ctx.skada
    assert skada.initializerError is None, skada.initializerError
    assert skada.version == "1.0.0"
    primary = skada.UI.GetPrimary(skada.UI)
    assert primary.frame is not None and primary.title is not None
    assert len(skada.UI.windows) == 1
    assert primary.db.snap is True and primary.db.snapDistance == 12 and primary.db.snapGap == 0 and primary.db.snapSize is True
    assert skada.db.profile.windowBorderStyle == "solid"
    border = skada.db.profile.windowBorderColor
    assert border[1] == 0.10 and border[2] == 0.11 and border[3] == 0.14
    assert skada.UI.visualActive is None
    ctx.run(r'''
      local frame = Skada.UI:GetPrimary().frame
      local border = Skada.db.profile.windowBorderColor
      local edges = rawget(frame, "skadaBorderEdges")
      assert(edges and edges[1].vertexR == border[1] and
        edges[1].vertexG == border[2] and edges[1].vertexB == border[3],
        "default bordered window did not load with its configured color")
      assert(table.getn(edges) == 4 and edges[1].height == 1 and
        edges[2].height == 1 and edges[3].width == 1 and edges[4].width == 1,
        "primary window border is not one pixel on every side")
      assert(not rawget(Skada.UI:GetPrimary().frame, "skadaShadow"),
        "default bordered window created the grey outer glow")
      local originalCount = table.getn(Skada.tickers)
      local healthyCalls = 0
      Skada:RegisterTicker("test-failing", 0.01, function() error("expected ticker failure") end)
      Skada:RegisterTicker("test-healthy", 0.01, function() healthyCalls = healthyCalls + 1 end)
      Skada.frame.OnUpdate(Skada.frame, 0.02)
      assert(healthyCalls == 1, "a failing ticker prevented the next ticker from running")
      while table.getn(Skada.tickers) > originalCount do table.remove(Skada.tickers) end
    ''')
