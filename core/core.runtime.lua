local Skada = (_G or getfenv(0)).Skada

Skada.name = Skada.name or "Skada"
local metadataVersion = GetAddOnMetadata and GetAddOnMetadata(Skada.name, "Version")
Skada.version = metadataVersion or "development"
Skada.initializers = {}
Skada.eventHandlers = {}
Skada.tickers = {}
Skada.minimumTickerInterval = nil
Skada.subscribers = {}
Skada.RenderPolicy = nil
Skada.dirty = true
Skada.initialized = false

local type = type
local tostring = tostring
local table_getn = table.getn
local table_insert = table.insert

Skada.defaults = Skada.Defaults.schema
local ApplyDefaults = Skada.Defaults.ApplyDefaults
local Common = Skada.Common

function Skada:RegisterInitializer(func, name)
  table_insert(self.initializers, {
    func = func,
    name = name or "component",
  })
end

local function recomputeMinimumTickerInterval(skada)
  local minimum
  local tickerIndex
  for tickerIndex = 1, table_getn(skada.tickers) do
    if not minimum or skada.tickers[tickerIndex].interval < minimum then
      minimum = skada.tickers[tickerIndex].interval
    end
  end
  skada.minimumTickerInterval = minimum
end

function Skada:RegisterTicker(name, interval, callback)
  local tickers = self.tickers
  local tickerIndex
  for tickerIndex = 1, table_getn(tickers) do
    if tickers[tickerIndex].name == name then
      tickers[tickerIndex].interval = interval
      tickers[tickerIndex].callback = callback
      recomputeMinimumTickerInterval(self)
      return
    end
  end
  table_insert(tickers, { name = name, interval = interval, callback = callback, elapsed = 0 })
  if not self.minimumTickerInterval or interval < self.minimumTickerInterval then
    self.minimumTickerInterval = interval
  end
end

function Skada:UnregisterTicker(name)
  local tickers = self.tickers
  local tickerIndex
  for tickerIndex = 1, table_getn(tickers) do
    if tickers[tickerIndex].name == name then
      table.remove(tickers, tickerIndex)
      recomputeMinimumTickerInterval(self)
      return true
    end
  end
  return false
end

function Skada:Subscribe(name, callback)
  local list = self.subscribers[name]
  if not list then
    list = {}
    self.subscribers[name] = list
  end
  table_insert(list, callback)
end

function Skada:Publish(name, payload1, payload2, payload3, payload4, payload5, payload6, payload7)
  local list = self.subscribers[name]
  if not list then return end
  local subscriberIndex, ok, message
  for subscriberIndex = 1, table_getn(list) do
    ok, message = pcall(list[subscriberIndex], payload1, payload2, payload3, payload4, payload5, payload6, payload7)
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
  table_insert(handlers, func)
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

  local initializerIndex, initializer, ok, message
  for initializerIndex = 1, table_getn(self.initializers) do
    initializer = self.initializers[initializerIndex]
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

frame:SetScript("OnEvent", function(self, eventName, payloadOne, payloadTwo, payloadThree, payloadFour, payloadFive, payloadSix, payloadSeven)
  if not eventName then
    eventName = event
    payloadOne, payloadTwo, payloadThree, payloadFour, payloadFive, payloadSix, payloadSeven = arg1, arg2, arg3, arg4, arg5, arg6, arg7
  end

  if eventName == "ADDON_LOADED" then
    if payloadOne == Skada.name then
      Skada:Initialize()
    end
  end

  if not Skada.initialized then return end
  local handlers = Skada.eventHandlers[eventName]
  if handlers then
    local handlerIndex, ok, message
    for handlerIndex = 1, table_getn(handlers) do
      ok, message = pcall(handlers[handlerIndex], eventName, payloadOne, payloadTwo, payloadThree, payloadFour, payloadFive, payloadSix, payloadSeven)
      if not ok then
        Skada:Print("Event handler failed (" .. eventName .. "): " .. tostring(message))
      end
    end
  end
end)

local displayElapsed = 0
local tickerElapsed = 0
local DISPLAY_UPDATE_INTERVAL = 0.25
frame:SetScript("OnUpdate", function(self, elapsed)
  if not Skada.initialized then return end

  displayElapsed = displayElapsed + elapsed
  tickerElapsed = tickerElapsed + elapsed

  local now
  local minimumTickerInterval = Skada.minimumTickerInterval
  if minimumTickerInterval and tickerElapsed >= minimumTickerInterval then
    local accumulated = tickerElapsed
    tickerElapsed = 0
    now = GetTime()
    local tickers = Skada.tickers
    local tickerIndex, ticker, ok, message
    for tickerIndex = 1, table_getn(tickers) do
      ticker = tickers[tickerIndex]
      ticker.elapsed = ticker.elapsed + accumulated
      if ticker.elapsed >= ticker.interval then
        ticker.elapsed = 0
        ok, message = pcall(ticker.callback, now)
        if ok then
          ticker.lastError = nil
        elseif ticker.lastError ~= message then
          ticker.lastError = message
          Skada:Print("Ticker failed (" .. ticker.name .. "): " .. tostring(message))
        end
      end
    end
  end

  local policy = Skada.RenderPolicy
  if not policy then return end

  if displayElapsed >= DISPLAY_UPDATE_INTERVAL then
    displayElapsed = 0
    now = now or GetTime()
    if policy.ShouldRebuild and policy:ShouldRebuild(now) then
      policy:Rebuild(now)
      Skada.dirty = false
    end
  end

  if policy.ShouldAnimate and policy:ShouldAnimate(now) then
    policy:Animate(now)
  end
end)
