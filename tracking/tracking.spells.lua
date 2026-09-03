local Skada = (_G or getfenv(0)).Skada

local SpellRegistry = {}
Skada.SpellRegistry = SpellRegistry

local interruptNames = {
  ["Kick"] = true,
  ["Pummel"] = true,
  ["Shield Bash"] = true,
  ["Counterspell"] = true,
  ["Earth Shock"] = true,
  ["Spell Lock"] = true,
}

function SpellRegistry:RememberSpell(sourceName, spellName, spellID)
  if not sourceName or not spellName or not spellID then return end
  local spells = self.spellIDs[sourceName]
  if not spells then
    spells = {}
    self.spellIDs[sourceName] = spells
  end
  spells[spellName] = spellID
end

function SpellRegistry:GetSpellID(sourceName, spellName)
  if spellName == "Auto Attack" or spellName == "Auto Hit" then return 6603 end
  local spells = sourceName and self.spellIDs[sourceName]
  return spells and spells[spellName] or nil
end

function SpellRegistry:GetSpellIcon(spellID)
  if not spellID then return nil end
  local cached = self.iconCache[spellID]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local texture
  if C_Spell and C_Spell.GetSpellTexture then
    texture = C_Spell.GetSpellTexture(spellID)
    if texture == "" then texture = nil end
  end
  self.iconCache[spellID] = texture or false
  return texture
end

function SpellRegistry:IsInterruptSpell(spellID, spellName)
  if spellID and self.interruptCache[spellID] ~= nil then
    return self.interruptCache[spellID]
  end

  local result = interruptNames[spellName] and true or false
  if not result and spellID and C_Spell and C_Spell.GetSpellMechanicByID then
    local mechanic = C_Spell.GetSpellMechanicByID(spellID)
    result = mechanic == 26
    if not result and C_Spell.GetSpellEffectMechanics then
      local effects = C_Spell.GetSpellEffectMechanics(spellID)
      if effects then
        local effectIndex
        for effectIndex = 1, 3 do
          if effects[effectIndex] == 26 then result = true break end
        end
      end
    end
  end

  if spellID then self.interruptCache[spellID] = result end
  return result
end
