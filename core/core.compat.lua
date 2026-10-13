-- Skada's private fixes for this 1.12 client. Nothing here replaces or adds
-- a global another addon can see: every fix lives on SkadaCompat and
-- Skada's own files take it as a local (`local table_getn =
-- SkadaCompat.Table.getn`). Other addons keep exactly the client they would
-- have without Skada loaded; the one shared frame Skada touches, the color
-- picker, is only adjusted while Skada itself has it open. The test harness
-- lints Skada's files for any direct use of the global table library.
local SkadaCompat = {}
(_G or getfenv(0)).SkadaCompat = SkadaCompat

-- string.match: this client's Lua is 5.1, so a native string.match exists
-- -- but addons that load before Skada can clobber it, and one does.
-- RollFor 4.8.1's src\vanilla\backport.lua assigns a pure-Lua string.match
-- built on string.find that returns ONLY the captures and ignores `init`,
-- so every capture-less pattern returns nil for every input (every /skada
-- command died on "attempt to concatenate a nil value"). Probe whatever is
-- installed with the shapes that broke (capture-less match, honoured
-- `init`, multiple captures) and keep it only when it passes; Skada
-- otherwise matches through string.find. The global is left as found.
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
local match = string.match
if not matchIsCorrect(match) then match = matchViaFind end
if not matchIsCorrect(match) then
  -- Even string.find can't match "[A-Za-z]%-[0-9]": the engine really does
  -- mis-parse that range order. "[a-zA-Z]" is the same character set, so the
  -- rewrite is lossless; it costs one gsub per call and only when engaged.
  local rangeBlindMatch = match
  match = function(value, pattern, init)
    return rangeBlindMatch(value, (gsub(pattern, "A%-Za%-z", "a-zA-Z")), init)
  end
end
SkadaCompat.Match = match

-- This client's table library (Lua 5.1 with LUA_COMPAT_GETN) tracks an
-- array's length as a side fact separate from its contents. Anything that
-- writes a table without going through insert/remove/setn leaves that fact
-- stale: remove(t) then returns nil on entries that were only ever
-- assigned, and the native sort and concat read the stale count -- seen in
-- game as damage windows sorted in scrambled order and concatenations
-- coming back empty. Skada's arrays go through this private library
-- instead, which derives every length from the table's actual contents.
do
  local rawget, rawset = rawget, rawset
  local sizes = setmetatable({}, { __mode = "k" })
  local function checkint(value)
    if type(value) == "number" and math.floor(value) == value and value >= 0 then return value end
    return nil
  end
  -- Every read and write below is raw, as the native C table library's
  -- are: a table with an __index metamethod must never see the length
  -- probe. A cached length that still sits on live content resumes the
  -- scan from there instead of from index 1, so the `t[getn(t) + 1] = v`
  -- append stays linear (measured in game: 5000 such appends take 5 ms,
  -- against 147 ms for the client's own getn).
  local function getn(t)
    local n = checkint(rawget(t, "n"))
    if n then return n end
    local cached = sizes[t]
    if cached and (cached == 0 or rawget(t, cached) ~= nil) then
      n = cached
      while rawget(t, n + 1) ~= nil do n = n + 1 end
      if n ~= cached then sizes[t] = n end
      return n
    end
    local i = 1
    while rawget(t, i) ~= nil do i = i + 1 end
    sizes[t] = i - 1
    return i - 1
  end
  -- Records a length insert/remove has just made true. Going through setn
  -- would ask getn for the old length after the content already changed --
  -- a full rescan on every call, quadratic over any list built or drained.
  local function noteLength(t, n)
    if checkint(rawget(t, "n")) then rawset(t, "n", n) else sizes[t] = n end
  end
  -- A shrink is a length contract, not a note beside the data: the tail is
  -- cleared so content and tracked length agree again.
  local function setn(t, n)
    if not checkint(rawget(t, "n")) then
      local i
      for i = n + 1, getn(t) do rawset(t, i, nil) end
    end
    noteLength(t, n)
  end
  -- Fixed parameters, never `...`: this client builds an argument table
  -- for every vararg call (measured in game: ~125 bytes a call). Without a
  -- vararg count, one function cannot tell insert(t, pos, nil) from an
  -- append, so the append and the positional form are two functions. A nil
  -- value inserts nothing: it could only ever have opened a hole in the list.
  local function insert(t, value)
    if value == nil then return end
    local n = getn(t)
    rawset(t, n + 1, value)
    noteLength(t, n + 1)
  end
  local function insertAt(t, pos, value)
    if value == nil then return end
    local n = getn(t) + 1
    if pos > n then n = pos end
    local j
    for j = n, pos + 1, -1 do rawset(t, j, rawget(t, j - 1)) end
    rawset(t, pos, value)
    noteLength(t, n)
  end
  local function remove(t, index)
    local n = getn(t)
    if n <= 0 then return end
    index = index or n
    local removed = rawget(t, index)
    local j
    for j = index, n - 1 do rawset(t, j, rawget(t, j + 1)) end
    rawset(t, n, nil)
    noteLength(t, n - 1)
    return removed
  end

  -- The native sort reads the same side-tracked length, so it is replaced
  -- by an in-place introsort driven by getn: O(n log n) work and O(log n)
  -- stack on any input. Bounded like the native auxsort, so a comparator
  -- that is not a strict order (`a <= b`) raises instead of walking the
  -- partition scan off the end of the range forever.
  local function invalidOrder()
    error("invalid order function for sorting", 3)
  end
  local function siftDown(t, comp, root, size, offset)
    local value = rawget(t, offset + root)
    local child = root * 2
    while child <= size do
      if child < size and comp(rawget(t, offset + child), rawget(t, offset + child + 1)) then
        child = child + 1
      end
      if not comp(value, rawget(t, offset + child)) then break end
      rawset(t, offset + root, rawget(t, offset + child))
      root = child
      child = root * 2
    end
    rawset(t, offset + root, value)
  end
  local function swap(t, first, second)
    local value = rawget(t, first)
    rawset(t, first, rawget(t, second))
    rawset(t, second, value)
  end
  local function heapsort(t, comp, lo, hi)
    local size, offset = hi - lo + 1, lo - 1
    local root
    for root = math.floor(size / 2), 1, -1 do siftDown(t, comp, root, size, offset) end
    local last
    for last = size, 2, -1 do
      swap(t, lo, offset + last)
      siftDown(t, comp, 1, last - 1, offset)
    end
  end
  local function introsort(t, comp, lo, hi, depth)
    while hi - lo > 12 do
      if depth == 0 then heapsort(t, comp, lo, hi); return end
      depth = depth - 1
      local pivot = rawget(t, math.floor((lo + hi) / 2))
      local left, right = lo, hi
      repeat
        while comp(rawget(t, left), pivot) do
          left = left + 1
          if left > hi then invalidOrder() end
        end
        while comp(pivot, rawget(t, right)) do
          right = right - 1
          if right < lo then invalidOrder() end
        end
        if left <= right then
          swap(t, left, right)
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
      local value, previous = rawget(t, index), index - 1
      while previous >= lo and comp(value, rawget(t, previous)) do
        rawset(t, previous + 1, rawget(t, previous))
        previous = previous - 1
      end
      rawset(t, previous + 1, value)
    end
  end
  local function ascending(a, b) return a < b end
  local function sort(t, comp)
    local size = getn(t)
    if size < 2 then return end
    local depth, remaining = 0, size
    while remaining > 1 do
      depth = depth + 2
      remaining = math.floor(remaining / 2)
    end
    introsort(t, comp or ascending, 1, size, depth)
  end

  -- The native concat defaults its end index from the side-tracked length
  -- too; hand it the real one.
  local nativeConcat = table.concat
  local function concat(t, sep, i, j)
    return nativeConcat(t, sep, i or 1, j or getn(t))
  end

  SkadaCompat.Table = {
    getn = getn,
    setn = setn,
    insert = insert,
    insertAt = insertAt,
    remove = remove,
    sort = sort,
    concat = concat,
  }
end

-- Sets `strata` on frame and on every frame beneath it.
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
-- to parent + 1, all the way down. This client's SetFrameLevel and
-- SetParent never reach children. Larger gaps set on purpose (Skada's own
-- row layers in ui.rows.lua) are left alone.
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
-- positional arguments, so nothing in Skada may call HookScript (the test
-- harness lints for it).
function SkadaCompat.AppendScript(frame, name, handler)
  local previous = frame:GetScript(name)
  frame:SetScript(name, function(...)
    if previous then previous(...) end
    handler(...)
  end)
end

-- Frames for Skada's own UI. GetWidth()/GetHeight() answer from the rect of
-- the last render pass, so a frame sized by two opposing anchors reads 0
-- until the next frame -- even right after an explicit SetWidth/SetHeight.
-- Layout that sizes a child from such a read the moment it is built would
-- inherit 0, so the explicit size answers while the rect still reads 0;
-- once rendered, the real rect wins.
local nativeCreateFrame = CreateFrame
local function rememberExplicitSize(frame, setterName, getterName, explicitKey)
  local nativeSetter, nativeGetter = frame[setterName], frame[getterName]
  if not (nativeSetter and nativeGetter) then return end
  frame[setterName] = function(self, size)
    rawset(self, explicitKey, size)
    return nativeSetter(self, size)
  end
  frame[getterName] = function(self)
    local rendered = nativeGetter(self)
    if not rendered or rendered == 0 then return rawget(self, explicitKey) or rendered end
    return rendered
  end
end

function SkadaCompat.CreateFrame(frameType, name, parent, template)
  local frame = nativeCreateFrame(frameType, name, parent, template)
  if not frame then return frame end
  rememberExplicitSize(frame, "SetWidth", "GetWidth", "skadaExplicitWidth")
  rememberExplicitSize(frame, "SetHeight", "GetHeight", "skadaExplicitHeight")
  return frame
end

-- The Blizzard ColorPickerFrame is shared. When Skada's color control
-- raises it, the new strata and level never reach its children on this
-- client -- the Okay and Cancel buttons and the opacity slider stay under
-- the picker's own backdrop, which swallows every click on them (reported
-- in game: it could be opened but never closed). Skada claims the picker
-- before raising it. A picker already open (another addon's session, or
-- another Skada swatch) is closed first the way its Cancel button closes
-- it, so that session's cancel callback restores what its live preview
-- changed; the Show that follows the claim then fires OnShow again. The claim
-- then records the strata and level of the picker and every frame beneath it.
-- While
-- Skada owns the picker its children are re-layered on show and it stops
-- re-raising itself over them; on hide every recorded frame gets its own
-- strata and level back, the toplevel flag returns and ownership ends.
local function recordLayering(frame, records)
  SkadaCompat.Table.insert(records, { frame = frame, strata = frame:GetFrameStrata(), level = frame:GetFrameLevel() })
  local children = { frame:GetChildren() }
  local childIndex = 1
  while children[childIndex] do
    recordLayering(children[childIndex], records)
    childIndex = childIndex + 1
  end
end

local colorPickerRecords

function SkadaCompat.ClaimColorPicker()
  local picker = ColorPickerFrame
  if not picker then return end
  if picker:IsShown() then
    local cancel = picker.cancelFunc
    picker:Hide()
    if cancel then cancel(picker.previousValues) end
  end
  local records = {}
  recordLayering(picker, records)
  colorPickerRecords = records
end

do
  local picker = ColorPickerFrame
  if picker and picker.GetChildren then
    local restoreToplevel = false
    SkadaCompat.AppendScript(picker, "OnShow", function()
      if not colorPickerRecords then return end
      SkadaCompat.ApplyStrata(picker, picker:GetFrameStrata())
      SkadaCompat.FixLevels(picker)
      if (not picker.IsToplevel) or picker:IsToplevel() then
        picker:SetToplevel(false)
        restoreToplevel = true
      end
    end)
    SkadaCompat.AppendScript(picker, "OnHide", function()
      local owned = colorPickerRecords
      if not owned then return end
      colorPickerRecords = nil
      local recordIndex, record
      for recordIndex = 1, SkadaCompat.Table.getn(owned) do
        record = owned[recordIndex]
        if record.strata then record.frame:SetFrameStrata(record.strata) end
        if record.level then record.frame:SetFrameLevel(record.level) end
      end
      if restoreToplevel then
        restoreToplevel = false
        picker:SetToplevel(true)
      end
    end)
  end
end
