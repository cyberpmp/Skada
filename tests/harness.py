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
        if filename.startswith("libs/"):
            continue  # vendored third-party code; not ours to lint
        source = (ROOT / filename).read_text(encoding="utf-8")
        declared = set(LOCAL_RE.findall(source))
        for name in set(ALIAS_RE.findall(source)):
            assert name in declared, (
                f"{filename}: {name} used but never declared with "
                f"'local {name} = <module>.<fn>'"
            )


def lint_script_hooks():
    """The client's HookScript runs the original handler without its
    positional arguments (AceGUI's sizer handler died on a nil frame in game
    and the dialog stayed glued to the mouse); Skada chains scripts through
    SkadaCompat.AppendScript instead."""
    for filename in toc_load_list():
        if filename.startswith("libs/"):
            continue
        source = (ROOT / filename).read_text(encoding="utf-8")
        assert ":HookScript(" not in source, (
            f"{filename}: use SkadaCompat.AppendScript; the client's HookScript "
            f"drops the original handler's arguments"
        )


def load_addon():
    """Load the addon in a stubbed environment.

    Chunks are invoked with no arguments, matching the OctoWoW client: addon
    chunks receive no varargs and share the global environment (the addon's
    own _G-or-getfenv(0) bootstrap in core/core.common.lua relies on this).
    """
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS_PATH.read_text(encoding="utf-8"))
    loadfile = lua.globals().loadfile
    files = toc_load_list()
    # Load in exact .toc order. string.match is nilled right after
    # core/core.compat.lua: Skada's own hand-written files keep the
    # vanilla-Lua-5.0-purity guard that catches accidental Lua-5.1-only
    # stdlib usage (the compat layer itself is exempt — its probe/repair
    # code is about string.match, not a user of it). (When the vendored
    # Ace3 stack under libs/ still existed, the nil point was right after
    # the last libs/ file instead, since that code needed
    # string.match/split/trim present.)
    match_nil_after_index = next(
        (index for index, filename in enumerate(files)
         if filename == "core/core.compat.lua"),
        None,
    )
    for index, filename in enumerate(files):
        chunk = loadfile(str(ROOT / filename))
        chunk()
        if index == match_nil_after_index:
            lua.execute("string.match = nil")
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