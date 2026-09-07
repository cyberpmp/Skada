"""Repeatable host-side timings; these are not measurements of in-game FPS."""

from statistics import median
from time import perf_counter

from harness import load_addon


def measure(label, callback, repetitions=5):
    callback()  # Warm caches before timing.
    samples = []
    for _ in range(repetitions):
        started = perf_counter()
        callback()
        samples.append((perf_counter() - started) * 1000)
    print(f"{label}: {median(samples):.2f} ms median ({repetitions} runs)")


def main():
    lua, _ = load_addon()
    print("Stubbed Lua runtime; compare runs on the same machine/runtime.")
    parser = lua.eval('''function()
      for i = 1, 50000 do
        Skada.Parser:OnCombatMessage("CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 1.")
      end
    end''')
    measure("50,000 damage messages", parser)
    factory = lua.eval('''function(size, order)
      local values = {}
      return function()
        for pass = 1, 200 do
          for i = 1, size do
            if order == "sorted" then values[i] = i
            elseif order == "reverse" then values[i] = size - i
            elseif order == "equal" then values[i] = 1
            else values[i] = i * 37 - math.floor(i * 37 / size) * size end
          end
          table.sort(values)
        end
      end
    end''')
    for size in (40, 128, 512):
        for order in ("sorted", "reverse", "equal", "mixed"):
            measure(f"200 sorts, {size} entries, {order}", factory(size, order))


if __name__ == "__main__":
    main()
