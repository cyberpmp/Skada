local Skada = (_G or getfenv(0)).Skada

Skada.name = Skada.name or "Skada"
local metadataVersion = GetAddOnMetadata and GetAddOnMetadata(Skada.name, "Version")
Skada.version = metadataVersion or "development"
Skada.initializers = {}
Skada.eventHandlers = {}
Skada.tickers = {}
Skada.subscribers = {}
Skada.RenderPolicy = nil
Skada.dirty = true
Skada.initialized = false

local type = type
local tostring = tostring
local table_getn = table.getn

Skada.defaults = Skada.Defaults.schema
local ApplyDefaults = Skada.Defaults.ApplyDefaults
local Common = Skada.Common

function Skada:RegisterInitializer(func, name)
  self.initializers[table_getn(self.initializers) + 1] = {
    func = func,
    name = name or "component",
  }
end

function Skada:RegisterTicker(name, interval, fn)
  local tickers = self.tickers
  local i
  for i = 1, table_getn(tickers) do
    if tickers[i].name == name then
      tickers[i].interval = interval
      tickers[i].fn = fn
      return
    end
  end
  tickers[table_getn(tickers) + 1] = { name = name, interval = interval, fn = fn, elapsed = 0 }
end

function Skada:Subscribe(name, fn)
  local list = self.subscribers[name]
  if not list then
    list = {}
    self.subscribers[name] = list
  end
  list[table_getn(list) + 1] = fn
end

function Skada:Publish(name, a1, a2, a3, a4, a5, a6, a7)
  local list = self.subscribers[name]
  if not list then return end
  local i, ok, message
  for i = 1, table_getn(list) do
    ok, message = pcall(list[i], a1, a2, a3, a4, a5, a6, a7)
    if not ok then
      Skada:Print("Subscriber failed (" .. name .. "): " .. tostring(message))
    end
  end
end

function Skada:RegisterRenderPolicy(policy)
  self.RenderPolicy = policy
end

function Skada:RegisterEvent(eventName, func)
  local handlers = self.eventHandlers[eventName]
  if not handlers then
    handlers = {}
    self.eventHandlers[eventName] = handlers

    if C_EventUtils and C_EventUtils.IsEventValid then
      if C_EventUtils.IsEventValid(eventName) then
        self.frame:RegisterEvent(eventName)
      end
    else
      pcall(self.frame.RegisterEvent, self.frame, eventName)
    end
  end
  handlers[table_getn(handlers) + 1] = func
end

function Skada:MarkDirty()
  self.dirty = true
end

function Skada:Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8000Skada:|r " .. tostring(message))
  end
end

function Skada:FormatNumber(value)
  local profile = self.db and self.db.profile
  return Common.FormatNumber(value, profile and profile.numberFormat)
end

function Skada:GetClassColor(class)
  return Common.GetClassColor(class)
end

function Skada:SetCombatLogging(enabled, silent)
  enabled = enabled and true or false
  if LoggingCombat then
    LoggingCombat(enabled and 1 or 0)
    self.combatLogging = enabled
    self.db.profile.autoLog = enabled
    self:MarkDirty()
    if not silent then
      self:Print("Combat file logging " .. (enabled and "enabled" or "disabled") .. ".")
    end
    return true
  end
  if not silent then
    self:Print("The client does not expose LoggingCombat().")
  end
  return false
end

function Skada:Initialize()
  if self.initialized then return end

  SkadaDB = SkadaDB or {}
  ApplyDefaults(SkadaDB, self.defaults)
  self.db = SkadaDB

  local i, initializer, ok, message
  for i = 1, table_getn(self.initializers) do
    initializer = self.initializers[i]
    ok, message = pcall(initializer.func, self)
    if not ok then
      self.initializerError = initializer.name .. ": " .. tostring(message)
      self:Print("Could not initialize " .. self.initializerError)
    end
  end

  self.initialized = true
  if self.db.profile.autoLog then
    self:SetCombatLogging(true, true)
  else
    self.combatLogging = false
  end
  self:MarkDirty()
  self:Print("v" .. self.version .. " loaded. /skada opens settings.")
end

local frame = CreateFrame("Frame", "SkadaCoreFrame")
Skada.frame = frame
frame:RegisterEvent("ADDON_LOADED")

-- The 1.12 client passes event scripts no positional args unless the
-- client-wide modern script args toggle is on, so fall back to the vanilla
-- event/arg1..argN globals (same pattern as getClickButton in options).
frame:SetScript("OnEvent", function(self, eventName, a, b, c, d, e, f, g)
  if not eventName then
    eventName = event
    a, b, c, d, e, f, g = arg1, arg2, arg3, arg4, arg5, arg6, arg7
  end

  if eventName == "ADDON_LOADED" then
    if a == Skada.name then
      Skada:Initialize()
    end
  end

  if not Skada.initialized then return end
  local handlers = Skada.eventHandlers[eventName]
  if handlers then
    local i, ok, message
    for i = 1, table_getn(handlers) do
      ok, message = pcall(handlers[i], eventName, a, b, c, d, e, f, g)
      if not ok then
        Skada:Print("Event handler failed (" .. eventName .. "): " .. tostring(message))
      end
    end
  end
end)

local displayElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
  if not Skada.initialized then return end

  displayElapsed = displayElapsed + elapsed

  local now = GetTime()
  local tickers = Skada.tickers
  local i, ticker, ok, message
  for i = 1, table_getn(tickers) do
    ticker = tickers[i]
    ticker.elapsed = ticker.elapsed + elapsed
    if ticker.elapsed >= ticker.interval then
      ticker.elapsed = 0
      ok, message = pcall(ticker.fn, now)
      if ok then
        ticker.lastError = nil
      elseif ticker.lastError ~= message then
        ticker.lastError = message
        Skada:Print("Ticker failed (" .. ticker.name .. "): " .. tostring(message))
      end
    end
  end

  local policy = Skada.RenderPolicy
  if not policy then return end

  if displayElapsed >= Skada.db.profile.updateRate then
    displayElapsed = 0
    if policy.ShouldRebuild and policy:ShouldRebuild(now) then
      policy:Rebuild(now)
      Skada.dirty = false
    end
  end

  if policy.ShouldAnimate and policy:ShouldAnimate(now) then
    policy:Animate(now)
  end
end)
