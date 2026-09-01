local Skada = (_G or getfenv(0)).Skada

local GroupObserver = {}
Skada.GroupObserver = GroupObserver

local table_getn = table.getn

function GroupObserver:ObserveGroup(recordNew)
  if not self.auraAPI or not Skada.Data.groupTokens then return end
  local i
  for i = 1, table_getn(Skada.Data.groupTokens) do
    self:ScanAll(Skada.Data.groupTokens[i], recordNew, GetTime())
  end
end

Skada:RegisterEvent("RAID_ROSTER_UPDATE", function()
  local tracking = Skada.Tracking
  if tracking then tracking:ObserveGroup(false) end
end)
Skada:RegisterEvent("PARTY_MEMBERS_CHANGED", function()
  local tracking = Skada.Tracking
  if tracking then tracking:ObserveGroup(false) end
end)
