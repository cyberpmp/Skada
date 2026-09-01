"""Suite: performance - 50k-message parser throughput must not retain memory."""

from harness import Context


def run(ctx: Context):
    retained_kb = ctx.eval('''
      function()
        collectgarbage("collect")
        local before = collectgarbage("count")
        for i = 1, 50000 do
          Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 1.")
        end
        collectgarbage("collect")
        return collectgarbage("count") - before
      end
    ''')()
    assert retained_kb < 256, retained_kb