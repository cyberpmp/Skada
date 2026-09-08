-- Fills in globals this 1.12 client doesn't provide, or provides in a broken
-- state, for Skada's own code and for any addon loaded after Skada that
-- needs them (BigDebuffs ships its own Ace3 and leans on the CreateFrame
-- wrapper further down). Every addition is guarded so a client that already
-- provides one of these keeps its real, native implementation untouched --
-- with two deliberate exceptions, noted inline.

-- string.match: this client's Lua is 5.1 (the table.getn/setn side-table
-- behaviour handled further down is Lua 5.1's LUA_COMPAT_GETN to the letter),
-- so a native string.match exists -- but addons that load before Skada can
-- clobber it, and one does. RollFor 4.8.1's src\vanilla\backport.lua assigns
-- a pure-Lua string.match built on string.find that returns ONLY the captures
-- and ignores `init`, so every capture-less pattern returns nil for every
-- input. Skada.Common.Match binds string.match at load time, and slash
-- command parsing is a capture-less pattern -- with RollFor enabled (it is,
-- on every character of this install) every /skada command died on "attempt
-- to concatenate a nil value" from the bound match returning
-- nothing. Two earlier fixes shipped and failed because both built on the
-- clobbered function: a `strmatch` global and a wrapper around string.match
-- that rewrote "[A-Za-z]" to "[a-zA-Z]" (RollFor's version returns nil for
-- that pattern in either order). That rewrite came from an in-game bisection
-- blaming the native pattern engine's range handling; since those probes ran
-- with RollFor's clobber in place, the engine theory is unconfirmed and is
-- only applied below if the engine itself demonstrably needs it.
--
-- Probe whatever string.match is installed with the shapes that broke
-- (capture-less match, honoured `init`, multiple captures) and replace it
-- only when the probe fails, so a correct native one stays untouched. The
-- global `strmatch` alias that other addons bind at load time gets
-- the same treatment.
local strfind, strsub, gsub = string.find, string.sub, string.gsub
local function matchViaFind(value, pattern, init)
  local first, last, capture1, capture2, capture3, capture4, capture5,
    capture6, capture7, capture8, capture9 = strfind(value, pattern, init)
  if not first then return nil end
  if capture1 == nil then return strsub(value, first, last) end
  return capture1, capture2, capture3, capture4, capture5, capture6, capture7,
    capture8, capture9
end
local function matchIsCorrect(match)
  if type(match) ~= "function" then return false end
  local ok, whole, fromInit, settingKey, settingValue = pcall(function()
    return match("AceConfigDialog-3.0", "[A-Za-z]%-[0-9]"),
      match("v1 v2", "v(%d)", 3),
      match("width=700", "^(%w+)=(%w+)$")
  end)
  return ok and whole == "g-3" and fromInit == "2"
    and settingKey == "width" and settingValue == "700"
end
if not matchIsCorrect(string.match) then
  string.match = matchViaFind
end
if not matchIsCorrect(string.match) then
  -- Even string.find can't match "[A-Za-z]%-[0-9]": the engine really does
  -- mis-parse that range order. "[a-zA-Z]" is the same character set, so the
  -- rewrite is lossless; it costs one gsub per call and only when engaged.
  local rangeBlindMatch = string.match
  string.match = function(value, pattern, init)
    return rangeBlindMatch(value, (gsub(pattern, "A%-Za%-z", "a-zA-Z")), init)
  end
end
if not matchIsCorrect(strmatch) then strmatch = string.match end

-- string.split ALREADY EXISTS on this client but is not drop-in compatible
-- with the Blizzard strsplit(delimiters, value) contract the chat command
-- dispatcher (SlashCmdList handlers, strsplit-based addon code) expects:
-- this client's native string.split was confirmed via in-game testing to
-- feed table.concat something other than clean strings ("table contains
-- non-strings") for some inputs. Unlike every other addition in this file,
-- this one is NOT guarded — it deliberately overrides the native, broken
-- implementation with a verified-correct one rather than deferring to it.
local gmatch = string.gmatch or string.gfind
function string.split(delimiters, value)
  local pieces = {}
  local piece
  for piece in gmatch(value, "([^" .. delimiters .. "]+)") do
    table.insert(pieces, piece)
  end
  return unpack(pieces)
end
strsplit = string.split

if not string.trim then
  function string.trim(value)
    local _, _, trimmed = string.find(value, "^%s*(.-)%s*$")
    return trimmed
  end
end
if not strtrim then strtrim = string.trim end

if not loadstring and load then loadstring = load end
if not unpack and table.unpack then unpack = table.unpack end
if not floor then floor = math.floor end
if not ceil then ceil = math.ceil end
if not max then max = math.max end
if not min then min = math.min end
if not wipe then
  function wipe(target)
    local key
    for key in pairs(target) do target[key] = nil end
    return target
  end
end
if not hooksecurefunc then
  function hooksecurefunc(nameOrTable, nameOrHook, maybeHook)
    local target, name, hook
    if type(nameOrTable) == "table" then
      target, name, hook = nameOrTable, nameOrHook, maybeHook
    else
      target, name, hook = _G or getfenv(0), nameOrTable, nameOrHook
    end
    local original = target[name]
    target[name] = function(...)
      if original then original(...) end
      return hook(...)
    end
  end
end

-- This client's table.getn/insert/remove (like real Lua 5.0's) track an
-- array's length as a side fact separate from its actual contents, rather
-- than deriving it live the way Lua 5.1+'s # operator does. That's fine as
-- long as everything mutates a table through table.insert/remove — but any
-- Lua-5.1-idiomatic code appends via `t[#t+1] = v`, which is invisible to
-- this client's length tracking, so table.remove(t) (no index -> removes at
-- the tracked length) returns nil on entries that were only ever added that
-- way, even though t[1] is clearly non-nil. Confirmed via in-game testing:
-- this broke the settings dialog's tree with "bad argument #1 to 'pairs'
-- (table expected, got nil)" from exactly that pattern. Fixed the same way
-- as string.split above: unconditionally replace all four with self-healing
-- versions that fall back to a real boundary scan whenever the tracked
-- length doesn't match what's actually in the table, instead of trusting a
-- length that native-style mutation could have silently invalidated.
do
  local sizes = setmetatable({}, { __mode = "k" })
  local function checkint(value)
    if type(value) == "number" and math.floor(value) == value and value >= 0 then return value end
    return nil
  end
  local function realgetn(t)
    local n = checkint(rawget(t, "n"))
    if n then return n end
    n = sizes[t]
    if n and ((n == 0 and t[1] == nil) or (n > 0 and t[n] ~= nil and t[n + 1] == nil)) then
      return n
    end
    local i = 1
    while t[i] ~= nil do i = i + 1 end
    sizes[t] = i - 1
    return i - 1
  end
  local function setn(t, n)
    if checkint(rawget(t, "n")) then rawset(t, "n", n) else
      -- A shrink is a length contract, not a note beside the data. Lua-5.0
      -- callers (TurtleMail's recipient autocomplete, for one) do
      -- table.setn(list, 0) to clear a list, refill it with table.insert,
      -- then setn-truncate it to a display count while the table still
      -- physically holds every candidate. Letting the tail survive desyncs
      -- every later length read -- our rescan answers the physical length
      -- (stale entries at the front, fresh inserts behind them, popups
      -- sized from every match on the realm) and the native global getn
      -- binary-searches the same -- so a shrink nils the tail and content
      -- and tracked length agree again.
      local i
      for i = n + 1, realgetn(t) do t[i] = nil end
      sizes[t] = n
    end
  end
  table.getn = realgetn
  table.setn = setn
  table.insert = function(t, ...)
    if select("#", ...) <= 1 then
      local n = realgetn(t)
      local value = ...
      t[n + 1] = value
      setn(t, n + 1)
    else
      local pos, value = ...
      local n = realgetn(t) + 1
      if pos > n then n = pos end
      local j
      for j = n, pos + 1, -1 do t[j] = t[j - 1] end
      t[pos] = value
      setn(t, n)
    end
  end
  table.remove = function(t, index)
    local n = realgetn(t)
    if n <= 0 then return end
    index = index or n
    local removed = t[index]
    local j
    for j = index, n - 1 do t[j] = t[j + 1] end
    t[n] = nil
    setn(t, n - 1)
    return removed
  end

  -- table.sort is a native/C function we cannot patch by reassigning pieces
  -- of it the way table.getn/insert/remove were above -- confirmed in-game
  -- to suffer the exact same side-tracked-length problem: the main meter's
  -- damage/healing windows showed every actor's value computed correctly but
  -- in scrambled, non-descending order. Every sorted list in Skada is
  -- rebuilt each cycle via Common.Wipe (which calls table.setn(t, 0) -- now
  -- our polyfill above, not whatever native mechanism table.sort's C
  -- implementation actually consults) followed by fresh table.insert calls;
  -- if table.sort determines "how many elements to sort" from that same
  -- native side fact rather than live content, it sorts against a stale
  -- count left over from a *previous*, larger render, comparing real entries
  -- against nil holes past the real end -- which does not crash (the
  -- comparator function is never necessarily called against the nil tail for
  -- small real-element counts) but silently corrupts the ordering of the
  -- real elements at the front. Use an in-place introsort driven by realgetn.
  -- The previous last-pivot quicksort took quadratic time and linear stack
  -- depth on sorted or equal values. This global shim also serves other
  -- addons, so bound every input to O(n log n) work and O(log n) stack space.
  local function siftDown(t, comp, root, size, offset)
    local value = t[offset + root]
    local child = root * 2
    while child <= size do
      if child < size and comp(t[offset + child], t[offset + child + 1]) then child = child + 1 end
      if not comp(value, t[offset + child]) then break end
      t[offset + root] = t[offset + child]
      root = child
      child = root * 2
    end
    t[offset + root] = value
  end
  local function heapsort(t, comp, lo, hi)
    local size, offset = hi - lo + 1, lo - 1
    local root
    for root = math.floor(size / 2), 1, -1 do siftDown(t, comp, root, size, offset) end
    local last
    for last = size, 2, -1 do
      t[lo], t[offset + last] = t[offset + last], t[lo]
      siftDown(t, comp, 1, last - 1, offset)
    end
  end
  local function introsort(t, comp, lo, hi, depth)
    while hi - lo > 12 do
      if depth == 0 then heapsort(t, comp, lo, hi); return end
      depth = depth - 1
      local pivot = t[math.floor((lo + hi) / 2)]
      local left, right = lo, hi
      repeat
        while comp(t[left], pivot) do left = left + 1 end
        while comp(pivot, t[right]) do right = right - 1 end
        if left <= right then
          t[left], t[right] = t[right], t[left]
          left, right = left + 1, right - 1
        end
      until left > right
      -- Recurse only into the smaller side, keeping stack depth logarithmic.
      if right - lo < hi - left then
        introsort(t, comp, lo, right, depth)
        lo = left
      else
        introsort(t, comp, left, hi, depth)
        hi = right
      end
    end
    -- Insertion sort avoids partition overhead on small ranges.
    local index
    for index = lo + 1, hi do
      local value, previous = t[index], index - 1
      while previous >= lo and comp(value, t[previous]) do
        t[previous + 1] = t[previous]
        previous = previous - 1
      end
      t[previous + 1] = value
    end
  end
  local function ascending(a, b) return a < b end
  table.sort = function(t, comp)
    local size = realgetn(t)
    if size < 2 then return end
    local depth, remaining = 0, size
    while remaining > 1 do
      depth = depth + 2
      remaining = math.floor(remaining / 2)
    end
    introsort(t, comp or ascending, 1, size, depth)
  end

  -- table.concat was left alone above because it doesn't mutate anything --
  -- but on this client it's built on the exact same side-tracked "n" as
  -- getn/insert/remove/sort (real Lua 5.0's table library shares one
  -- length fact across all of them), and every write above now happens
  -- through this shim's own Lua-level assignments rather than the native
  -- C insert/setn calls that side-tracked "n" is updated by. So a table
  -- built via this file's table.insert (used throughout AceOO's Factory
  -- for its class-identity uid: table.insert into a table, table.sort,
  -- table.concat to stringify it) carries the right content and the right
  -- table.getn answer, but the client's native table.concat still reads
  -- an "n" that was never told about any of it -- confirmed in-game: it
  -- silently concatenates as empty, which starved AceOO's uid string down
  -- to "" for every mixin combination, so its Factory handed back
  -- whichever class happened to be cached under that same empty key
  -- instead of the right one (seen in game as SuperAPI's FuBarPlugin-based
  -- minimap button silently missing methods and never showing). Wrap it so
  -- it always reads the same length this shim already tracks correctly.
  local realConcat = table.concat
  table.concat = function(t, sep, i, j)
    return realConcat(t, sep, i or 1, j or realgetn(t))
  end

  -- unpack(t) with no explicit end index has the identical exposure: real
  -- Lua 5.1's unpack defaults its end index from the same native side-
  -- tracked "n" table.concat did. string.split above (this file's own
  -- code, bound globally as strsplit for other addons to call too) builds
  -- its result via this file's table.insert and hands it to a bare
  -- unpack(pieces) -- the same shape as the table.concat bug, just not yet
  -- caught in the wild. Same fix.
  local realUnpack = unpack
  unpack = function(t, i, j)
    return realUnpack(t, i or 1, j or realgetn(t))
  end

  -- table.foreachi(t, f) is the last member of the same Lua-5.0 table
  -- family (insert/remove/getn/setn/concat/sort/foreachi all read or write
  -- one shared side-tracked "n" in real Lua 5.0) and nothing else in this
  -- file has touched it. Real Lua 5.1 dropped it outright, so only patch
  -- it if this client still carries it for old-addon compatibility; unlike
  -- concat/unpack it takes no i/j to hand it a bound, so it's replaced
  -- outright rather than wrapped, same as insert/remove/sort above.
  if table.foreachi then
    table.foreachi = function(t, f)
      local n = realgetn(t)
      local i
      for i = 1, n do
        local result = f(i, t[i])
        if result ~= nil then return result end
      end
    end
  end
end

-- AceGUI's EditBox/MultiLineEditBox widgets (BigDebuffs' copy)
-- unconditionally hooksecurefunc("ChatEdit_InsertLink", ...) at load time to
-- support shift-clicking chat links into a text field. ChatEdit_InsertLink is a
-- post-Vanilla FrameXML addition and doesn't exist here; the real client's
-- native hooksecurefunc refuses to hook a name that isn't already a
-- function ("target field is not a function"), so give it a harmless
-- no-op stand-in. Link-insertion simply won't do anything on this client,
-- which is fine — Skada's own option widgets don't rely on it.
if not ChatEdit_InsertLink then function ChatEdit_InsertLink() end end

-- Layering helpers, shared with options.lua and the SetParent shim below.
-- Reachable as a global because this file loads before core.common.lua
-- creates the Skada table.
local SkadaCompat = {}
(_G or getfenv(0)).SkadaCompat = SkadaCompat

-- Sets `strata` on frame and on every frame beneath it. The recursion is
-- the same shape as AceGUI's own fixstrata (AceGUIWidget-DropDown.lua),
-- which its dropdown pullout needs for exactly the reason below.
function SkadaCompat.ApplyStrata(frame, strata)
  frame:SetFrameStrata(strata)
  local children = { frame:GetChildren() }
  local childIndex = 1
  while children[childIndex] do
    SkadaCompat.ApplyStrata(children[childIndex], strata)
    childIndex = childIndex + 1
  end
end

-- Lifts any frame beneath `frame` whose level does not exceed its parent's
-- to parent + 1, all the way down. Larger gaps set on purpose (TreeGroup
-- rows, Skada's own row layers in ui.rows.lua) are left alone.
function SkadaCompat.FixLevels(frame)
  local parentLevel = frame:GetFrameLevel() or 0
  local children = { frame:GetChildren() }
  local childIndex, child = 1, nil
  while children[childIndex] do
    child = children[childIndex]
    if (child:GetFrameLevel() or 0) <= parentLevel then
      child:SetFrameLevel(parentLevel + 1)
    end
    SkadaCompat.FixLevels(child)
    childIndex = childIndex + 1
  end
end

-- Chains `handler` after whatever script `frame` already has for `name`,
-- passing on exactly the arguments the client supplied. The client's own
-- HookScript (added by its DLL) runs the original handler without its
-- positional arguments: seen in game as AceGUI's sizer handler dying on a
-- nil frame, which skipped StopMovingOrSizing and left the settings dialog
-- glued to the mouse. Nothing in Skada may call HookScript (the test
-- harness lints for it).
function SkadaCompat.AppendScript(frame, name, handler)
  local previous = frame:GetScript(name)
  frame:SetScript(name, function(...)
    if previous then previous(...) end
    handler(...)
  end)
end

-- Re-derives `frame`'s strata and level from `parent` (what a modern client
-- does inside SetParent) and then its whole subtree's.
function SkadaCompat.InheritLayering(frame, parent)
  local strata = parent.GetFrameStrata and parent:GetFrameStrata()
  if strata then SkadaCompat.ApplyStrata(frame, strata) end
  local parentLevel = parent.GetFrameLevel and parent:GetFrameLevel()
  if parentLevel and (frame:GetFrameLevel() or 0) <= parentLevel then
    frame:SetFrameLevel(parentLevel + 1)
  end
  SkadaCompat.FixLevels(frame)
end

-- What GetWidth/GetHeight should answer, given the client's raw answer and
-- the explicit size (if any) recorded by the SetWidth/SetHeight wrappers.
-- Two client facts, both from /skada uiprobe output: a frame sized by
-- anchors reads 0 until its first render, and after that it reports its
-- rendered size in SCREEN units (frame units times its effective scale),
-- while an explicitly sized frame reports frame units. At UI scale 0.71 the
-- dialog's 1064-wide content read 757, its 869-wide pane 618 and the
-- 847-wide scroll frame 602. AceGUI's Fill layout feeds such reads straight
-- back into SetWidth, so every rebuild after the first render shrank the
-- settings pane by the UI scale and the controls wrapped into fewer columns
-- with dead space on the right (seen in game, twice). For AceGUI's frames
-- (`.obj` set) an explicit size therefore wins outright, and a rendered
-- rect is divided by the effective scale; every other frame keeps the
-- client's raw answer, with the explicit size only filling in for a rect
-- that still reads 0.
local function reportedSize(frame, raw, explicitKey)
  local explicit = rawget(frame, explicitKey)
  if not frame.obj then
    if not raw or raw == 0 then return explicit or raw end
    return raw
  end
  if explicit then return explicit end
  if raw and raw > 0 then
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale()
    if scale and scale > 0 then return raw / scale end
  end
  return raw
end

-- CreateFrame itself has real gaps this client leaves open, confirmed via
-- in-game testing. Wrapping CreateFrame (rather than patching every call
-- site) keeps the fixes in one place; they stay generic and .obj-gated so
-- BigDebuffs' own Ace3 dialog keeps benefiting from them too.
local realCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template, ...)
  local frame
  if template == "OptionsListButtonTemplate" then
    -- Built from scratch below; see 1).
    frame = realCreateFrame(frameType, name, parent)
  else
    frame = realCreateFrame(frameType, name, parent, template, ...)
  end
  if not frame then return frame end

  -- 0) GetWidth()/GetHeight() answer from the rect of the last render pass,
  -- so a frame sized by two opposing anchors reads 0 until the next frame --
  -- even right after an explicit SetWidth/SetHeight. Any layout that sizes
  -- its child from exactly such a read, synchronously, the moment it is
  -- built (AceGUI's Fill layout, BigDebuffs' copy included) inherits width 0
  -- and flows every control into a single column (seen in game). Remember
  -- explicit sizes and answer with them while the rect is still 0; once
  -- rendered, the real rect wins -- corrected for the client's screen-unit
  -- reporting on AceGUI frames, see reportedSize.
  local realSetWidth, realGetWidth = frame.SetWidth, frame.GetWidth
  if realSetWidth and realGetWidth then
    frame.SetWidth = function(self, width)
      rawset(self, "skadaExplicitWidth", width)
      return realSetWidth(self, width)
    end
    frame.GetWidth = function(self)
      return reportedSize(self, realGetWidth(self), "skadaExplicitWidth")
    end
  end
  local realSetHeight, realGetHeight = frame.SetHeight, frame.GetHeight
  if realSetHeight and realGetHeight then
    frame.SetHeight = function(self, height)
      rawset(self, "skadaExplicitHeight", height)
      return realSetHeight(self, height)
    end
    frame.GetHeight = function(self)
      return reportedSize(self, realGetHeight(self), "skadaExplicitHeight")
    end
  end

  -- 1) "OptionsListButtonTemplate" (AceGUIContainer-TreeGroup.lua's tree
  -- sidebar rows -- BigDebuffs' Ace3 copy builds these). This client's
  -- FrameXML does carry a template by that name
  -- -- in game the rows came out 18px tall with the gold quest-log highlight
  -- -- but its OnLoad never populated the `.toggle`/`.text` fields TreeGroup
  -- indexes (CreateButton crashed on a nil `.toggle`), and what else its XML
  -- scripts do on this client is unknowable. So the template is bypassed
  -- above and the row is built here from scratch, identically in game and in
  -- the test harness: 175x18, the quest-log row highlight (LockHighlight marks
  -- the selected row with it), the label inset 8px and kept clear of the
  -- toggle, and the 14x14 expand/collapse toggle at the RIGHT edge (an early
  -- stand-in anchored it LEFT, over the label's first letter). TreeGroup
  -- re-anchors `.text`'s LEFT point and swaps the toggle's plus/minus textures
  -- on every refresh, so only what it never touches is set here.
  if template == "OptionsListButtonTemplate" then
    frame:SetWidth(175)
    frame:SetHeight(18)
    frame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local rowHighlight = frame.GetHighlightTexture and frame:GetHighlightTexture()
    if rowHighlight and rowHighlight.SetBlendMode then rowHighlight:SetBlendMode("ADD") end

    local toggle = realCreateFrame("Button", nil, frame)
    toggle:SetWidth(14)
    toggle:SetHeight(14)
    toggle:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    toggle:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
    toggle:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
    toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
    local toggleHighlight = toggle.GetHighlightTexture and toggle:GetHighlightTexture()
    if toggleHighlight and toggleHighlight.SetBlendMode then toggleHighlight:SetBlendMode("ADD") end
    toggle:Hide()
    frame.toggle = toggle

    local text = frame:CreateFontString(nil, "BACKGROUND")
    text:SetFontObject(GameFontNormalSmall)
    text:SetJustifyH("LEFT")
    text:SetHeight(18)
    text:SetPoint("LEFT", frame, "LEFT", 8, 0)
    text:SetPoint("RIGHT", frame, "RIGHT", -22, 0)
    frame.text = text
  end

  -- 1b) SetParent leaves the moved frame's strata and level where they were.
  -- AceGUI builds every widget under UIParent and only later hands it to its
  -- container with frame:SetParent(container.content); a modern client then
  -- re-derives the moved frame's strata and level from the new parent, this
  -- one does not (1.12-era code such as Dewdrop-2.0 re-applies both by hand
  -- right after every SetParent for the same reason). Seen in game via
  -- /skada uiprobe: the dialog root sat at the strata options.lua gives it
  -- while its reparented TreeGroup, ScrollFrame and every control inside
  -- kept UIParent's, so the root's own translucent backdrop drew over all of
  -- them (the "dark tint" across the sidebar and the pane) and, being
  -- mouse-enabled, took every click meant for them -- GetMouseFocus over a
  -- sidebar row answered with the unnamed root. Re-derive here on every
  -- SetParent into an AceGUI frame, subtree included, the way AceGUI's
  -- dropdown pullout already does for itself with fixlevels/fixstrata.
  -- AceGUI stamps `.obj` (the owning widget) on every frame it hands out as
  -- a parent, which keeps this to AceGUI frames (BigDebuffs' copy
  -- included): this CreateFrame wrapper is global, and addons loading after
  -- Skada keep the client's own reparenting rules for their frames.
  local realSetParent = frame.SetParent
  if realSetParent then
    frame.SetParent = function(self, parent)
      realSetParent(self, parent)
      if type(parent) == "table" and parent.obj then
        SkadaCompat.InheritLayering(self, parent)
      end
    end
  end

  -- 2) TreeGroup (tree row labels) and Keybinding call
  -- :SetNormalFontObject(...)/:SetHighlightFontObject(...) on Button frames
  -- to pick the label's font style (bold top-level rows vs. small indented
  -- ones); confirmed via in-game testing this client's Button type has
  -- neither method at all. TreeGroup's row buttons (BigDebuffs' Ace3 copy)
  -- render their actual visible label through a separately-managed `.text`
  -- FontString (see the OptionsListButtonTemplate fix above), not the
  -- button's own native font string, so apply the font there when present;
  -- fall back to the native GetFontString() otherwise (e.g. Keybinding's
  -- UIPanelButtonTemplate2 button, which sets its own text via :SetText()).
  -- Only SetNormalFontObject
  -- actually applies a font, since every call site here invokes it right
  -- before SetHighlightFontObject with the display font — a real client only
  -- swaps to the highlight font while hovered, which we can't track without
  -- an OnEnter/OnLeave hook; keeping the normal-state font as final is closer
  -- to correct than always showing the highlight font regardless of hover.
  if frameType == "Button" then
    if not frame.SetNormalFontObject then
      frame.SetNormalFontObject = function(self, fontObject)
        if type(fontObject) == "string" then
          fontObject = (_G or getfenv(0))[fontObject] or fontObject
        end
        local fontString = self.text or (self.GetFontString and self:GetFontString())
        if fontString and fontString.SetFontObject then
          fontString:SetFontObject(fontObject)
        end
      end
    end
    if not frame.SetHighlightFontObject then
      frame.SetHighlightFontObject = function() end
    end
    if not frame.SetDisabledFontObject then
      frame.SetDisabledFontObject = function() end
    end
  end

  return frame
end

-- The Blizzard ColorPickerFrame is shared: Skada's own color control and
-- AceGUI's ColorPicker widget (BigDebuffs' copy) both raise it to
-- FULLSCREEN_DIALOG and bump its level right before showing it. On this
-- client neither change reaches the frame's children -- the Okay and Cancel
-- buttons and the opacity slider keep the DIALOG strata and the levels their
-- XML gave them at load -- so the picker's own translucent backdrop drew
-- over its buttons and its mouse handling swallowed every click on them: it
-- could be opened from the settings but never closed (reported in game).
-- Re-derive the
-- children's layering from the frame every time it shows, the same way, and
-- keep it from re-raising itself over them on click while it is up; the
-- toplevel flag goes back on hide so the frame is left as the default UI
-- and other addons found it.
do
  local picker = ColorPickerFrame
  local appendScript = SkadaCompat.AppendScript
  if picker and picker.GetChildren then
    local restoreToplevel = false
    appendScript(picker, "OnShow", function()
      SkadaCompat.ApplyStrata(picker, picker:GetFrameStrata())
      SkadaCompat.FixLevels(picker)
      if (not picker.IsToplevel) or picker:IsToplevel() then
        picker:SetToplevel(false)
        restoreToplevel = true
      end
    end)
    appendScript(picker, "OnHide", function()
      if restoreToplevel then
        restoreToplevel = false
        picker:SetToplevel(true)
      end
    end)
  end
end
