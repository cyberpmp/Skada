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

    ctx.run('''
      local retainedActor = { name = "Old actor" }
      local retainedEntry = { label = "Old actor", actor = retainedActor }
      local displayOwner = { display = { retainedEntry } }
      Skada.UIPresenter.ClearDisplay(displayOwner)
      assert(retainedEntry.actor == nil and retainedEntry.label == nil,
        "display pool retained an actor after the visible entry was cleared")

      local realUnitExists = UnitExists
      local lookups = 0
      UnitExists = function(unit)
        lookups = lookups + 1
        return realUnitExists(unit)
      end
      Skada.Tracking.unitMissByName = {}
      Skada.Tracking:NoteDamage("Alice", "Unseen Performance Target", "Fireball", 1000)
      local firstLookupCount = lookups
      assert(firstLookupCount > 0)
      for i = 1, 100 do
        Skada.Tracking:NoteDamage("Alice", "Unseen Performance Target", "Fireball", 1000.1)
      end
      assert(lookups == firstLookupCount,
        "unresolved damage target repeated its unit-token scan per event")
      Skada.Tracking:NoteDamage("Alice", "Unseen Performance Target", "Fireball", 1000.6)
      assert(lookups > firstLookupCount, "unresolved damage target was never retried")
      UnitExists = realUnitExists
    ''')
