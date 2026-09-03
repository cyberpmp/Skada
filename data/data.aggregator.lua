local Skada = (_G or getfenv(0)).Skada

local DataAggregator = {}
Skada.DataAggregator = DataAggregator

local min = math.min
local max = math.max
local floor = math.floor
local table_getn = table.getn
local table_insert = table.insert

function DataAggregator:NewSet(name, now, isTotal)
  return {
    name = name,
    startTime = now,
    lastTime = now,
    duration = 0,
    actors = {},
    actorList = {},
    damage = 0,
    damageTaken = 0,
    healing = 0,
    effectiveHealing = 0,
    overhealing = 0,
    unverifiedHealing = 0,
    dispels = 0,
    interrupts = 0,
    cc = 0,
    ccBreaks = 0,
    ccDuration = 0,
    deaths = 0,
    isTotal = isTotal and true or false,
    hasData = false,
  }
end

function DataAggregator:TouchActor(actor, now)
  if not actor.firstTime then
    actor.firstTime = now
    actor.lastTime = now
    actor.activeTime = 1
    return
  end

  local delta = now - actor.lastTime
  if delta > 0 then
    actor.activeTime = actor.activeTime + min(delta, 5)
  end
  actor.lastTime = now
end

function DataAggregator:GetActor(set, name, identity)
  local actor = set.actors[name]
  if actor then return actor end

  actor = {
    name = name,
    guid = identity and identity.guid,
    class = identity and identity.class or "OTHER",
    damage = 0,
    damageTaken = 0,
    healing = 0,
    effectiveHealing = 0,
    overhealing = 0,
    unverifiedHealing = 0,
    dispels = 0,
    interrupts = 0,
    cc = 0,
    ccBreaks = 0,
    ccDuration = 0,
    deaths = 0,
    activeTime = 0,
  }
  set.actors[name] = actor
  table_insert(set.actorList, actor)
  return actor
end

function DataAggregator:AddSpell(actor, field, spellName, spellID, amount, critical)
  if not spellName then return end
  local spells = actor[field]
  if not spells then
    spells = {}
    actor[field] = spells
  end

  local spell = spells[spellName]
  if not spell then
    spell = {
      name = spellName,
      id = spellID,
      amount = 0,
      count = 0,
      critical = 0,
    }
    spells[spellName] = spell
  elseif spellID and not spell.id then
    spell.id = spellID
  end

  amount = amount or 0
  spell.amount = spell.amount + amount
  spell.count = spell.count + 1
  if critical then spell.critical = spell.critical + 1 end
  if amount > 0 then
    if not spell.minimum or amount < spell.minimum then spell.minimum = amount end
    if not spell.maximum or amount > spell.maximum then spell.maximum = amount end
  end
  return spell
end

local getActor = DataAggregator.GetActor
local addSpell = DataAggregator.AddSpell
local touchActor = DataAggregator.TouchActor

function DataAggregator:RecordDamageSet(set, actorName, sourceIdentity, targetActorName, targetIdentity, amount, spellName, spellID, critical, selfDamage, now, rawTargetName, mitigationType, mitigationAmount)
  set.hasData = true
  set.lastTime = now
  if actorName and not selfDamage then
    local actor = getActor(DataAggregator, set, actorName, sourceIdentity)
    actor.damage = actor.damage + amount
    set.damage = set.damage + amount
    actor.hits = (actor.hits or 0) + 1
    addSpell(DataAggregator, actor, "damageSpells", spellName, spellID, amount, critical)
    if rawTargetName then addSpell(DataAggregator, actor, "damageTargets", rawTargetName, nil, amount, critical) end
    if mitigationType then
      local mitigation = actor.mitigation
      if not mitigation then
        mitigation = {}
        actor.mitigation = mitigation
      end
      local observation = mitigation[mitigationType]
      if not observation then
        observation = { amount = 0, count = 0 }
        mitigation[mitigationType] = observation
      end
      observation.amount = observation.amount + (mitigationAmount or 0)
      observation.count = observation.count + 1
      actor.mitigated = (actor.mitigated or 0) + (mitigationAmount or 0)
    end
    touchActor(DataAggregator, actor, now)
  end
  if targetActorName then
    local targetActor = getActor(DataAggregator, set, targetActorName, targetIdentity)
    targetActor.damageTaken = targetActor.damageTaken + amount
    set.damageTaken = set.damageTaken + amount
    addSpell(DataAggregator, targetActor, "takenSpells", spellName or "Damage", spellID, amount, critical)
  end
end

function DataAggregator:RecordHealingSet(set, actorName, identity, amount, effective, overhealing, verified, spellName, spellID, critical, now, rawTargetName)
  set.hasData = true
  set.lastTime = now
  local actor = getActor(DataAggregator, set, actorName, identity)
  effective = effective or amount
  overhealing = overhealing or 0
  actor.healing = actor.healing + amount
  actor.effectiveHealing = actor.effectiveHealing + effective
  actor.overhealing = actor.overhealing + overhealing
  set.healing = set.healing + amount
  set.effectiveHealing = set.effectiveHealing + effective
  set.overhealing = set.overhealing + overhealing
  if not verified then
    actor.unverifiedHealing = actor.unverifiedHealing + amount
    set.unverifiedHealing = set.unverifiedHealing + amount
  end

  local spell = addSpell(DataAggregator, actor, "healingSpells", spellName, spellID, amount, critical)
  if spell then
    spell.effectiveHealing = (spell.effectiveHealing or 0) + effective
    spell.overhealing = (spell.overhealing or 0) + overhealing
    if not verified then spell.unverifiedHealing = (spell.unverifiedHealing or 0) + amount end
  end
  if rawTargetName then
    local target = addSpell(DataAggregator, actor, "healTargets", rawTargetName, nil, amount, critical)
    if target then
      target.effectiveHealing = (target.effectiveHealing or 0) + effective
      target.overhealing = (target.overhealing or 0) + overhealing
      if not verified then target.unverifiedHealing = (target.unverifiedHealing or 0) + amount end
    end
  end
  touchActor(DataAggregator, actor, now)
end

function DataAggregator:RecordPowerSet(set, actorName, identity, amount, spellName, spellID, powerType, now)
  set.hasData = true
  set.lastTime = now
  local actor = getActor(DataAggregator, set, actorName, identity)
  actor.power = (actor.power or 0) + amount
  set.power = (set.power or 0) + amount
  addSpell(DataAggregator, actor, "powerSpells", spellName, spellID, amount, false)
  local spells = actor.powerSpells
  local spell = spells and spells[spellName]
  if spell then spell.powerType = powerType end
  touchActor(DataAggregator, actor, now)
end

function DataAggregator:RecordCountSet(set, actorName, identity, field, detailField, detailName, spellID, count, now)
  set.hasData = true
  set.lastTime = now
  local actor = getActor(DataAggregator, set, actorName, identity)
  actor[field] = (actor[field] or 0) + count
  set[field] = (set[field] or 0) + count
  addSpell(DataAggregator, actor, detailField, detailName or field, spellID, count, false)
  touchActor(DataAggregator, actor, now)
end

function DataAggregator:RecordDeathSet(set, actorName, identity, now, killerName, killerSpell)
  set.hasData = true
  set.lastTime = now
  local actor = getActor(DataAggregator, set, actorName, identity)
  actor.deaths = actor.deaths + 1
  set.deaths = set.deaths + 1

  local log = actor.deathLog
  if not log then
    log = {}
    actor.deathLog = log
  end
  local index = (actor.deathLogCount or 0) + 1
  actor.deathLogCount = index

  local elapsed = max(0, now - set.startTime)
  local timeLabel = string.format("%d:%02d", floor(elapsed / 60), floor(elapsed % 60))
  local cause
  if killerName then
    cause = "Killed by " .. killerName .. (killerSpell and (" (" .. killerSpell .. ")") or "")
  else
    cause = "Unknown cause"
  end
  log["death" .. index] = { name = timeLabel, amount = index, count = 1, customText = cause }
end

function DataAggregator:RecordDurationSet(set, actorName, field, detailField, spellName, duration)
  local actor = set.actors[actorName]
  if not actor then return end
  actor[field] = (actor[field] or 0) + duration
  set[field] = (set[field] or 0) + duration
  local spells = actor[detailField]
  local spell = spells and spells[spellName]
  if spell then spell.duration = (spell.duration or 0) + duration end
end
