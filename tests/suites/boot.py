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
    ctx.run(r'''
      local originalCount = table.getn(Skada.tickers)
      local healthyCalls = 0
      Skada:RegisterTicker("test-failing", 0.01, function() error("expected ticker failure") end)
      Skada:RegisterTicker("test-healthy", 0.01, function() healthyCalls = healthyCalls + 1 end)
      Skada.frame.OnUpdate(Skada.frame, 0.02)
      assert(healthyCalls == 1, "a failing ticker prevented the next ticker from running")
      while table.getn(Skada.tickers) > originalCount do table.remove(Skada.tickers) end
    ''')