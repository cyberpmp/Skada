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
        # The game TOC uses backslash separators (the client's loader requires
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


PRIVATE_LIBRARY_RE = re.compile(
    r"(?<![\w.])(?:table\.(?:getn|setn|insert|remove|sort|concat|foreachi)\b"
    r"|unpack\(|string\.(?:match|split|trim)\b|:(?:match|split|trim)\(|strmatch\(|strsplit\(|strtrim\(|hooksecurefunc\()"
)


def lint_private_library():
    """Skada's files reach the table library and string helpers only through
    SkadaCompat (core/core.compat.lua). The client's own getn/sort/concat
    read a side-tracked length that goes stale, and the globals belong to
    every other addon, so Skada neither calls nor replaces them."""
    for filename in toc_load_list():
        if filename == "core/core.compat.lua":
            continue
        source = (ROOT / filename).read_text(encoding="utf-8")
        match = PRIVATE_LIBRARY_RE.search(source)
        assert match is None, (
            f"{filename}: {match.group(0)!r} uses a shared global; "
            f"take it from SkadaCompat instead"
        )


def lint_frame_factory():
    """Skada builds its frames through SkadaCompat.CreateFrame, which
    remembers explicit sizes so GetWidth/GetHeight read them before the first
    render. A file calling the client's CreateFrame gets frames that read 0
    until drawn, and layout that sizes children right after building them
    collapses."""
    for filename in toc_load_list():
        if filename == "core/core.compat.lua":
            continue
        source = (ROOT / filename).read_text(encoding="utf-8")
        if "CreateFrame(" in source:
            assert "local CreateFrame = SkadaCompat.CreateFrame" in source, (
                f"{filename}: calls CreateFrame without "
                f"`local CreateFrame = SkadaCompat.CreateFrame`"
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


SHARED_GLOBALS_SNAPSHOT = '''
TestSharedGlobals = {}
local libraryName, key, value
for _, libraryName in ipairs({ "table", "string", "math" }) do
  for key, value in pairs(_G[libraryName]) do
    TestSharedGlobals[libraryName .. "." .. key] = value
  end
end
for _, key in ipairs({ "CreateFrame", "unpack", "select", "hooksecurefunc", "wipe",
    "strsplit", "strmatch", "strtrim", "loadstring", "floor", "ceil", "max", "min",
    "ChatEdit_InsertLink" }) do
  TestSharedGlobals[key] = _G[key] or false
end
'''


def load_addon():
    """Load the addon in a stubbed environment.

    Chunks are invoked with no arguments, matching the WoW Vanilla
    1.12.1 client as run with ClassicAPI, where addon chunks receive no varargs and no _G
    and share the global environment (the addon's
    own _G-or-getfenv(0) bootstrap in core/core.common.lua relies on this).
    """
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS_PATH.read_text(encoding="utf-8"))
    loadfile = lua.globals().loadfile
    # Skada must leave every shared library and API global exactly as the
    # client had it; the boot suite compares against this snapshot.
    lua.execute(SHARED_GLOBALS_SNAPSHOT)
    files = toc_load_list()
    # Load in exact .toc order. lint_private_library keeps Skada's files off
    # string.match; the global stays as the stubs installed it.
    for filename in files:
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