local Skada = (_G or getfenv(0)).Skada

local GroupObserver = {}
Skada.GroupObserver = GroupObserver

local table_getn = table.getn

function GroupObserver:ObserveGroup(recordNew, now)
  if not self.auraAPI or not Skada.Data.groupTokens then return end
  local tokenIndex
  now = now or GetTime()
  for tokenIndex = 1, table_getn(Skada.Data.groupTokens) do
    self:ScanAll(Skada.Data.groupTokens[tokenIndex], recordNew, now)
  end
end

function GroupObserver:QueueGroupBaseline(unknownOnly, now)
  if not self.auraAPI or not Skada.Data.groupTokens then return end
  local tokenIndex
  for tokenIndex = 1, table_getn(Skada.Data.groupTokens) do
    self:QueueAuraBaseline(Skada.Data.groupTokens[tokenIndex], unknownOnly, now)
  end
end

local function handleGroupChanged()
  local tracking = Skada.Tracking
  if not tracking then return end
  local active = Skada.Data.active
  -- Known units continue through UNIT_AURA; a new baseline would suppress
  -- their next buff application while it waits in the baseline queue.
  tracking:QueueGroupBaseline(active, active and GetTime() or nil)
end

Skada:RegisterEvent("RAID_ROSTER_UPDATE", handleGroupChanged)
Skada:RegisterEvent("PARTY_MEMBERS_CHANGED", handleGroupChanged)
