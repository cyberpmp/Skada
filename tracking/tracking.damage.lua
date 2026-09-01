local Skada = (_G or getfenv(0)).Skada

local DamageWitness = {}
Skada.DamageWitness = DamageWitness

function DamageWitness:FindTargetUnit(targetName)
  if not targetName or targetName == "" then return nil end
  if targetName == "You" or targetName == YOU then return "player" end
  return Skada.Data:FindUnitByName(targetName)
end

function DamageWitness:GetLastDamageInfo(targetName)
  if not targetName then return nil end
  local unit = self:FindTargetUnit(targetName)
  local guid = unit and UnitGUID(unit)
  if not guid then return nil end
  return self.lastDamageByTarget[guid]
end

function DamageWitness:NoteDamage(sourceName, targetName, spellName, now)
  local unit = Skada.Data:FindUnitByName(targetName)
  local guid = unit and UnitGUID(unit)
  if not guid then return end
  local entry = self.lastDamageByTarget[guid]
  if not entry then
    entry = {}
    self.lastDamageByTarget[guid] = entry
  end
  entry.sourceName = sourceName
  entry.spellName = spellName
  entry.time = now
end
