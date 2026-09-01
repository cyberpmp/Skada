"""Shared harness for the Skada test suites.

Loads the addon exactly as the game would (TOC order), provides the stubbed
WoW environment, and lints upvalue aliases. Suites receive a Context carrying
the live Lua runtime and the loaded Skada namespace.
"""

from pathlib import Path
import re

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
STUBS_PATH = Path(__file__).resolve().parent / "stubs.lua"


def toc_load_list():
    entries = []
    for line in (ROOT / "Skada.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        assert line.endswith(".lua"), f"unexpected toc entry: {line!r}"
        # The game TOC uses backslash separators (the OctoWoW loader requires
        # them); normalize to forward slashes so the harness also runs on CI.
        entries.append(line.replace("\\", "/"))
    assert entries, "Skada.toc contained no loadable files"
    return entries


ALIAS_RE = re.compile(r"\b(?:table|math|string|os)_[a-z]+\b")
LOCAL_RE = re.compile(r"\blocal\s+([a-z]+_[a-z]+)\b")


def lint_upvalue_aliases():
    for filename in toc_load_list():
        source = (ROOT / filename).read_text(encoding="utf-8")
        declared = set(LOCAL_RE.findall(source))
        for name in set(ALIAS_RE.findall(source)):
            assert name in declared, (
                f"{filename}: {name} used but never declared with "
                f"'local {name} = <module>.<fn>'"
            )


def load_addon():
    """Load the addon in a stubbed environment.

    Chunks are invoked with no arguments, matching the OctoWoW client: addon
    chunks receive no varargs and share the global environment (the addon's
    own _G-or-getfenv(0) bootstrap in core/core.common.lua relies on this).
    """
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS_PATH.read_text(encoding="utf-8"))
    lua.execute("string.match = nil")
    loadfile = lua.globals().loadfile
    for filename in toc_load_list():
        chunk = loadfile(str(ROOT / filename))
        chunk()
    namespace = lua.globals().Skada
    namespace.Initialize(namespace)
    return lua, namespace


class Context:
    """Live Lua runtime + loaded addon, shared by every suite in order."""

    def __init__(self, lua, skada):
        self.lua = lua
        self.skada = skada

    def run(self, code):
        self.lua.execute(code)

    def eval(self, code):
        return self.lua.eval(code)

    def set_time(self, value):
        self.lua.globals().TestSetTime(value)

    def set_combat(self, value):
        self.lua.globals().TestSetCombat(value)

    def set_target(self, name, guid):
        self.lua.globals().TestSetTarget(name, guid)