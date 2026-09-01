"""Skada test suite orchestrator.

Loads the addon in a stubbed WoW environment (tests/stubs.lua via harness.py)
and runs the domain suites from tests/suites/ in a fixed order. Suites share
one Lua runtime and build on each other's state, so the sequence below is the
contract - do not reorder.

Entry point for CI and the release workflow: `python tests/run_tests.py`.
"""

import sys
import time
import traceback

from harness import Context, lint_upvalue_aliases, load_addon
from suites import (
    auras,
    boot,
    boss_detection,
    combat,
    debuffs,
    options,
    performance,
    presentation,
    render_loop,
    segments,
    threat,
    ui_chrome,
)

# Canonical execution order. Suites are stateful and sequential: later suites
# assert on fight data and history created by earlier ones.
SUITES = [
    boot,
    ui_chrome,
    combat,
    threat,
    presentation,
    performance,
    auras,
    segments,
    debuffs,
    render_loop,
    boss_detection,
    options,
]


def main():
    if "--list" in sys.argv[1:]:
        for suite in SUITES:
            print(f"{suite.__name__.rsplit('.', 1)[-1]:<16} {suite.__doc__.strip()}")
        return

    lint_upvalue_aliases()
    lua, skada = load_addon()
    ctx = Context(lua, skada)

    for suite in SUITES:
        name = suite.__name__.rsplit(".", 1)[-1]
        started = time.perf_counter()
        try:
            suite.run(ctx)
        except Exception:
            print(f"FAIL suite '{name}'", file=sys.stderr)
            traceback.print_exc()
            sys.exit(1)
        print(f"== {name} == ({(time.perf_counter() - started) * 1000:.0f} ms)")

    print("Skada test suite passed")


if __name__ == "__main__":
    main()