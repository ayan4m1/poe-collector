'use strict'

qs = require 'qs'
moment = require 'moment'
process = require 'process'
jsonfile = require 'jsonfile'

currency = require './currency'
elastic = require './elastic'
log = require './logging'

baseTypes = jsonfile.readFileSync("#{__dirname}/../data/BaseTypes.json")

slug = (input) -> input.trim().toLowerCase()

regexes =
  price:
    note: /\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/
    name: /\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/
  type:
    weapon: /^(Bow|Axe|Sword|Dagger|Mace|Staff|Claw|Sceptre|Wand|Fishing Rod)$/
    armour: /^(Helmet|Gloves|Boots|Body|Shield|Quiver)$/
    accessory: /^(Amulet|Belt|Ring)$/
    map: /^Travel to this Map by using it in the Eternal Laboratory/
    flask: /^Right click to drink/
    jewel: /^Place into an allocated Jewel Socket/
    leaguestone: /^Right-click to open your Legacy Panel/
  mods:
    damage: /([-+]?)(\d*\.?\d+%?) (to|increased|reduced|more|less)\s+(Chaos|Cold|Fire|Lightning|Burning|Spell|Projectile|Elemental|Area|Melee)?\s*Damage/
    defense: /([-+]?)(\d*\.?\d+%?) (to|increased|reduced) (Armour and Evasion Rating|Armour|Evasion Rating|Stun and Block Recovery)/
    offense: /([-+]?)(\d*\.?\d+%?) (to|increased|reduced|more|less) (Cast|Attack|Movement|Physical|Mine|Trap|Totem|Accuracy Rating|Projectile)\s*(and Cast|Throwing|Laying|Speed)?\s*(with Weapons|for Spells)?/
    block: /([-+]?)(\d*\.?\d+%?)(?: additional| to maximum)? (?:Chance to Block|Block Chance)( Spells)?\s*(?:with|while)?\s*(Staves|Shields|Dual Wielding)?/
    flatOffense: /Adds (\d+)( to (\d+))? (Chaos |Elemental |Fire |Physical |Cold |Lightning )?Damage(?: to (Attacks|Spells))?/
    reflect: /Reflects (\d+)( to (\d+))? (Cold|Fire|Lightning|Physical) Damage to( Melee)? Attackers( on Block)?/
    resist: /([-+]?)(\d+%) to (all )?(maximum )?(Lightning|Cold|Fire|Chaos|Elemental)(and (Lightning|Cold|Fire))? Resistance(s?)/
    dualResist: /([-+]?)(\d+%) to (Fire|Cold|Lightning) and (Fire|Cold|Lightning) Resistances/
    attribute: /([-+]?)(\d+) to (all )?(Attributes|Strength|Dexterity|Intelligence)( and (Dexterity|Intelligence))?/
    vitals: /([-+]?)(\d+%?) (increased|reduced|to)(?: maximum)? (Life|Mana|Energy Shield|Light Radius)( Recharge Rate)?/i
    gemLevel: /\+\d to Level of Socketed (Aura|Bow|Chaos|Cold|Elemental|Fire|Lightning|Melee|Minion|Strength|Support|Vaal|Spell)?\s*Gems/
    ailment: /(\d+%) (?:chance )?(to|increased) (Shock|Ignite|Freeze)( Duration on Enemies)?/
    resistPen: /Penetrates (\d+%) (Cold|Lightning|Fire|Chaos) Resistance/
    flaskUtility: /([-+]?)(\d+%) (increased|reduced) Flask (effect|Charges) (duration|gained|used)/
    flaskUtilityChance: /([-+]?)(\d+%) chance to (Avoid being)\s+(Chilled|Frozen) during (?:Flask)? effect/
    flaskAilment: /Removes (Bleeding|Burning|Curses|Freeze and Chill|Shock) on use/
    conversion: /(\d+%) of (Physical|Lightning|Cold|Fire) Damage Converted to (Lightning|Cold|Fire|Chaos) Damage/
    loot: /([\d+%]) increased (Rarity|Quantity) of Items found/
    recovery: /([-+]?)(\d*\.?\d+%?) (Life|Mana) (Regenerated per Second|gained on Kill)/
    critical: /([-+]?)(\d*\.?\d+%?) (increased|reduced|more|less|to)(\s+Global)?\s+Critical Strike (Chance|Multiplier)\s*(?:while|with|for)?\s*(Dual Wielding|Fire|Cold|Lightning|Elemental|Spells)?/
    ailmentPrevent: /^Cannot be (Ignited|Frozen|Knocked Back|Poisoned)/
    leechPermyriad: /(\d*\.?\d+%?) of (Cold|Fire|Lightning|Physical Attack) Damage Leeched as (Life|Mana)/
    leechFlat: /([-+]?)(\d*\.?\d+) (Life|Mana|Energy Shield) gained for each Enemy hit by (?:your )?(Attacks|Spells)/
    stunOffense: /([-+]?)(\d*\.?\d+%?) (increased|reduced) (Enemy Stun Threshold|Stun Duration on Enemies)( while using a Flask)?/
    regen: /(\d*\.?\d+) (Life|Mana) Regenerated per second/
    breach: /Properties are doubled while in a Breach/
    attrReqs: /(\d+)% reduced Attribute Requirements/

modOperators =
  increased: (a, b) -> a * (b + 1.0)
  reduced: (a, b) -> a * (1.0 - b)
  less: (a, b) -> a ? 0 - b ? 0
  more: (a, b) -> a ? 0 + b ? 0
  to: (a, b, sign) -> if sign is '+' then modOperators.more(a, b) else modOperators.less(a, b)

modParsers =
  dualResist: (mod, result) ->
    [ fullText, sign, value, first, second ] = mod
    buckets = [ slug(first), slug(second) ]
    result.defense.resist.elemental[buckets[0]] = modOperators.more(result.defense.resist.elemental[buckets[0]], value, sign)
    result.defense.resist.elemental[buckets[1]] = modOperators.more(result.defense.resist.elemental[buckets[1]], value, sign)
  attrReqs: (mod, result) ->
    [ fullText, value ] = mod
    result.stats.reduced.attributeRequirements = modOperators.reduced(result.stats.reduced.attributeRequirements, value)
  stunOffense: (mod, result) ->
    [ fullText, percent, value, op, type, flask ] = mod
    log.as.silly('no-op stun offense')
    #when 'Enemy Stun Threshold'
    #when 'Stun Duration on Enemies'
  leechPermyriad: (mod, result) ->
    [ fullText, value, subType, type ] = mod
    subType = 'physical' if subType is 'Physical Attack'
    value = parseFloat(value.replace('%', '') / 100.0)
    bucket = slug(type)
    subBucket = slug(subType)
    result.offense.leech[bucket][subBucket] = modOperators.increased(result.offense.leech[bucket][subBucket], value)
  leechFlat: (mod, result) ->
    [ fullText, sign, value, type, subType ] = mod
    type = 'shield' if type is 'Energy Shield'
    bucket = slug(type)
    result.offense.onHit[bucket] = modOperators.increased(result.offense.leech[bucket], value)
  leech: (mod, result) ->
    [ fullText, sign, value, source, type ] = mod
    bucket = slug(type)
    floatVal = parseFloat(value)
    switch source
      when 'Cold', 'Fire', 'Lightning'
        subBucket = slug(source)
        result.offense.leech.elemental[subBucket][bucket] = modOperators.more(result.offense.leech.elemental[subBucket][bucket], value, sign)
      when 'Physical Attack'
        result.offense.leech[bucket] = modOperators.more(result.offense.leech[bucket], floatVal, sign)
  regen: (mod, result) ->
    [ fullText, value, type ] = mod
    bucket = slug(type)
    floatVal = parseFloat(value)
    result.stats.regen[bucket].percent = modOperators.more(result.stats.regen[bucket].percent, floatVal)
  breach: (mod, result) ->
    result.stats.breach = true
  ailmentPrevent: (mod, result) ->
    [ fullText, type ] = mod
    bucket = slug(type)
    if type is 'Knocked Back'
      bucket = 'knockedBack'
    result.defense.prevent[bucket] = true
  critical: (mod, result) ->
    [ fullText, sign, value, op, global, type, subBucket ] = mod

    bucket = slug(type)
    operator = modOperators[op]

    if subBucket is 'Dual Wielding'
      result.offense.critical.dualWielding[bucket] = operator(result.offense.critical.dualWielding[bucket])
      return

    if global is 'Global'
      result.offense.critical.global[bucket] = operator(result.offense.critical.global[bucket], value)

    if subBucket is 'Spells'
      result.offense.critical.spell[bucket] = operator(result.offense.critical.spell[bucket], value)
  recovery: (mod, result) ->
    [ fullText, sign, value, first, second ] = mod
    bucket = slug(first)
    if second is 'gained on Kill'
      result.offense.onKill[bucket] = modOperators.increased(result.offense.onKill[bucket])
    else
      result.stats.regen[bucket] = modOperators.to(result.stats.regen[bucket], value, sign)
  flaskUtilityChance: (mod, result) ->
    [ fullText, sign, value, type ] = mod
  flaskUtility: (mod, result) ->
    [ fullText, sign, value, op, type, verb ] = mod
    operator = modOperators[op]
    bucket = slug(type)
    switch bucket
      when 'effect'
        result.flask.effect = operator(result.flask.effect, value, sign)
      when 'charges'
        result.flask.chargesUsed = operator(result.flask.chargesUsed, value, sign)
  damage: (mod, result) ->
    [ fullText, sign, value, op, type ] = mod
    operator = modOperators[op]
    switch type
      when 'Cold', 'Fire', 'Lightning'
        bucket = slug(type)
        result.offense.damage.elemental[bucket] = operator(result.offense.damage.elemental[bucket], value)
      when 'Chaos'
        result.offense.damage.chaos.percent = operator(result.offense.damage.chaos.percent, value)
      when 'Projectile'
        result.offense.damage.projectile = operator(result.offense.damage.projectile, value)
      when 'Spell'
        result.offense.damage.spell.all = operator(result.offense.damage.spell.all, value)
      when 'Elemental'
        result.offense.damage.elemental.percent = operator(result.offense.damage.elemental.percent, value)
      when 'Physical'
        result.offense.damage.physical.percent = operator(result.offense.damage.physical.percent, value)
      when 'Area'
        result.offense.damage.areaOfEffect = operator(result.offense.damage.areaOfEffect, value)
      when 'Melee'
        # todo: what counts as melee?
        result.offense.damage.physical.percent = operator(result.offense.damage.physical.percent, value)
        #  result.offense.damage.physical.min = operator(result.offense.damage.physical.min, value)
        #  result.offense.damage.physical.max = operator(result.offense.damage.physical.max, value)
  loot: (mod, result) ->
    [ fullText, value, type ] = mod
    bucket = slug(type)
    result.stats.item[bucket] = modOperators.increased(result.stats.item[bucket], value)
  conversion: (mod, result) ->
    [ fullText, value, sourceType, destType ] = mod
    log.as.silly('no-op damage conversion')
  resistPen: (mod, result) ->
    [ fullText, value, type ] = mod
    bucket = slug(type)
    value = parseInt(value.replace('%', '')) * 0.01
    result.offense.damage.penetration[bucket] += value
  flaskAilment: (mod, result) ->
    [ fullText, type ] = mod
    if mod.indexOf(' and ') >= 0
      console.dir(mod)
    bucket = slug(type)
    result.flask.removeAilment[bucket] = true
  ailment: (mod, result) ->
    [ fullText, value, op, type, duration ] = mod
    bucket = slug(type)
    subBucket = if duration is ' Duration on Enemies' then 'duration' else 'chance'
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%', ''))
    if isPercent then value *= 0.01
    # "to" verb is always positive here, so hard-code sign
    operator = modOperators[op]
    result.offense.ailment[bucket][subBucket] = operator(result.offense.ailment[bucket][subBucket], value, '+')
  defense: (mod, result) ->
    [ fullText, sign, value, op, type ] = mod
    return new Error(mod) unless value?
    operator = modOperators[op]
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%', ''))
    if isNaN(value) then value = parseFloat(value)
    if isPercent then value *= 0.01
    bucket = if isPercent then 'percent' else 'flat'

    switch type.trim()
      when 'Armour'
        result.defense.armour[bucket] = operator(result.defense.armour[bucket], value, sign)
      when 'Evasion Rating'
        result.defense.evasion[bucket] = operator(result.defense.evasion[bucket], value, sign)
      when 'Armour and Evasion Rating'
        result.defense.armour[bucket] = operator(result.defense.armour[bucket], value, sign)
        result.defense.evasion[bucket] = operator(result.defense.evasion[bucket], value, sign)
      when 'Armour and Energy Shield'
        result.defense.armour[bucket] = operator(result.defense.armour[bucket], value, sign)
        result.defense.shield[bucket] = operator(result.defense.shield[bucket], value, sign)
      when 'Armour, Evasion and Energy Shield'
        result.defense.armour[bucket] = operator(result.defense.armour[bucket], value, sign)
        result.defense.shield[bucket] = operator(result.defense.shield[bucket], value, sign)
        result.defense.evasion[bucket] = operator(result.defense.evasion[bucket], value, sign)
      when 'Stun and Block Recovery'
        result.defense.stunRecovery = operator(result.defense.stunRecovery, value, sign)
  flatOffense: (mod, result) ->
    [ fullText, min, bogus, max, type, target ] = mod
    bucket = slug(type)
    range =
      min: parseInt(min)
      max: parseInt(max)
    return if isNaN(range.min) or isNaN(range.max)

    switch type
      when 'Elemental'
        result.offense.damage.elemental.all.flat.min += range.min
        result.offense.damage.elemental.all.flat.max += range.max
      when 'Cold', 'Lightning', 'Fire'
        result.offense.damage.elemental[bucket].flat.min += range.min
        result.offense.damage.elemental[bucket].flat.max += range.max
      when 'Physical', 'Chaos'
        result.offense.damage[bucket].flat.min += range.min
        result.offense.damage[bucket].flat.max += range.max
  offense: (mod, result) ->
    [ fullText, sign, value, op, first, second, third, fourth] = mod
    return new Error(mod) unless value?
    isPercent = value.indexOf('%')
    value = parseInt(value.replace('%', ''))
    if isPercent then value *= 0.01

    operator = modOperators[op]

    if first is 'Accuracy Rating'
      bucket = if isPercent then 'percent' else 'flat'
      result.offense.accuracyRating[bucket] = operator(result.offense.accuracyRating[bucket], value, sign)

    return unless third is 'Speed'
    switch first
      when 'Attack'
        result.offense.attackSpeed = operator(result.offense.attackSpeed, value)
        if second is 'and Cast'
          result.offense.castSpeed = operator(result.offense.castSpeed, value)
      when 'Cast'
        result.offense.castSpeed = operator(result.offense.castSpeed, value)
      when 'Projectile'
        result.offense.projectileSpeed = operator(result.offense.projectileSpeed, value)
      when 'Movement'
        result.stats.movementSpeed = operator(result.stats.movementSpeed, value)
  block: (mod, result) ->
    [ fullText, sign, value, spell, weapon ] = mod
    return new Error(mod) unless value?
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%',''))
    if isPercent then value *= 0.01
    return if isNaN(value)

    if spell?
      result.defense.blockChance.spells += value
    else if weapon is 'Dual Wielding'
      result.defense.blockChance.dualWielding += value
    else
      # todo: break this out into the types
      result.defense.blockChance.weapons += value
  reflect: (mod, result) ->
    [ fullText, min, bogus, max, type, melee, block ] = mod
    range =
      min: parseInt(min)
      max: parseInt(max)
    return if isNaN(range.min) or isNaN(range.max)

    # todo: work this out
    #switch type
    #  when 'Physical'
    #  when 'Cold', 'Fire', 'Lightning'
  resist: (mod, result) ->
    [ fullText, sign, value, all, maximum, type ] = mod
    return new Error(mod) unless value?
    isPercent = value.indexOf('%') > 0
    value = parseFloat(value.replace('%',''))
    if isPercent then value *= 0.01

    operator = modOperators.to
    switch type
      when 'Elemental'
        if all is 'all ' and maximum is 'maximum '
          bucket = 'maximum'
          subBucket = 'all'
        else if all is 'all '
          bucket = 'elemental'
          subBucket = 'all'
        else
          return log.as.error('unexpected Elemental non-all non-max resist...')

        result.defense.resist[bucket][subBucket] = operator(result.defense.resist[bucket][subBucket], value, sign)
      when 'Chaos'
        result.defense.resist.chaos = operator(result.defense.resist.chaos, value, sign)
      when 'Cold', 'Fire', 'Lightning'
        bucket = maximum?.trim()
        subBucket = slug(type)
        if bucket is 'maximum'
          result.defense.resist[bucket][subBucket] = operator(result.defense.resist[bucket][subBucket], value, sign)
        else
          result.defense.resist.elemental[subBucket] = operator(result.defense.resist.elemental[subBucket], value, sign)

    if all is 'all '
      result.pseudo.resist.all = operator(result.pseudo.resist.all, value, sign)
    else if maximum is 'maximum '
      result.pseudo.resist.maximum = operator(result.pseudo.resist.maximum, value, sign)

    result.pseudo.resist.elemental = operator(result.pseudo.resist.elemental, value, sign)
  attribute: (mod, result) ->
    [ fullText, sign, value, all, first, second ] = mod
    value = parseInt(value)
    return new Error(mod) if isNaN(value)

    operator = modOperators.to
    if all is 'all'
      result.stats.attribute.all = operator(result.stats.attribute.all, value, sign)
    else
      firstCat = first.toLowerCase().substring(0, 3)
      result.stats.attribute[firstCat] = operator(result.stats.attribute[firstCat], value, sign)
      if second?
        secondCat = second.toLowerCase().substring(0, 3)
        result.stats.attribute[secondCat] = operator(result.stats.attribute[secondCat], value, sign)
  vitals: (mod, result) ->
    [ fullText, sign, value, op, type, recharge ] = mod
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%', ''))
    if isPercent then value *= 0.01
    bucket = if isPercent then 'percent' else 'flat'

    op = op.toLowerCase()
    operator = modOperators[op]
    if recharge is 'Recharge Rate'
      result.defense.shield.recharge = operator(result.defense.shield.recharge, value, sign)
    else
      switch type
        when 'Life'
          result.stats.life[bucket] = operator(result.stats.life[bucket], value, sign)
        when 'Mana'
          result.stats.mana[bucket] = operator(result.stats.mana[bucket], value, sign)
        when 'Energy Shield'
          result.defense.shield[bucket] = operator(result.defense.shield[bucket], value, sign)
        when 'Light Radius'
          result.stats.reduced.inverseLightRadius = operator(result.stats.reduced.inverselightRadius, value, sign)
  gemLevel: (mod, result) ->
    [ value, type ] = mod
    value = parseInt(value)
    return if isNaN(value)
    type = type ? 'all'
    bucket = slug(type)
    result.gemLevel[bucket] = value

parseMod = (mod, result) ->
  foundMatch = false
  for type, regex of regexes.mods
    matchData = mod.match(regex)
    continue unless matchData?
    foundMatch = true
    return unless modParsers[type]?
    modParsers[type](matchData, result)
    break

  #log.as.warn("N #{mod}") unless matchData?
  #log.as.info("Y #{mod}") if matchData?
  result.modifiers.push(mod)

parseDamageType = (id) ->
  switch id
    when 1 then return 'Physical'
    when 4 then return 'Fire'
    when 5 then return 'Cold'
    when 6 then return 'Lightning'
    when 7 then return 'Chaos'
    else return 'Unknown'

parseCurrency = (item, result) ->
  raw =
    if item.note? then item.note.match(regexes.price.note)
    else if item.stashName? then item.stashName.match(regexes.price.name)

  return unless raw?.length > 0
  factor = 0
  quantity = 0
  raw.shift()
  for term in raw
    continue if term is 'price' or term is 'b/o'
    break unless currency.values[item.league]?
    if isNaN(parseFloat(term))
      for key, regex of currency.regexes
        if regex.test(term)
          for curr in currency.values[item.league]
            if regex.test(curr.name)
              log.as.silly("#{term} matches #{curr.name} matches #{key} - #{curr.value}")
              factor = curr.value
              break
        break if factor > 0
    else quantity = parseFloat(term)

  return unless factor > 0 and quantity > 0
  result.price =
    raw: raw
    chaos: factor * quantity

parseRange = (range) ->
  results = range.match(/(\d+)-(\d+)/)

  {
    min: parseInt(results[0])
    max: parseInt(results[1])
  }

parseProperty = (prop, result) ->
  switch prop.name
    when /^(One|Two) Handed (Sword|Axe|Mace)/
      hands = prop.name.match(/(One|Two)/).pop()
      result.gearType = "#{hands} Handed #{weaponType} Weapon"
    when 'Bow', 'Staff', 'Claw', 'Wand'
      result.gearType = prop.name
    when 'Level'
      result.level = parseInt(prop.values[0][0])
    when 'Quality'
      result.quality = parseInt(prop.values[0][0].replace(/[%\\+]/g, ''))
    when 'Evasion Rating'
      result.defense.evasion.flat += parseInt(prop.values[0][0])
    when 'Energy Shield'
      result.defense.shield.flat += parseInt(prop.values[0][0])
    when 'Armour'
      result.defense.armour.flat += parseInt(prop.values[0][0])
    when 'Physical Damage'
      result.offense.damage.physical.flat = parseRange(prop.values[0][0])
    when 'Chaos Damage'
      result.offense.damage.chaos.flat = parseRange(prop.values[0][0])
    when 'Elemental Damage'
      damage = {}

      for value in prop.values
        range = parseRange(value[0])
        damageType = parseDamageType(value[1])
        damageKey = damageType.toLowerCase()
        damage[damageKey] = range

      for type, range of damage
        result.offense.damage.elemental[type].flat = range
    when 'Critical Strike Chance'
      result.offense.critical.chance = parseFloat(prop.values[0][0].replace('%', '')) / 100.0
    when 'Attacks per Second'
      result.offense.attacksPerSecond = parseFloat(prop.values[0][0])
    when 'Weapon Range'
      result.offense.meleeRange = parseInt(prop.values[0][0])
    when 'Stack Size'
      stackInfo = prop.values[0][0].split(/\//)
      result.stack =
        count: stackInfo[0]
        maximum: stackInfo[1]
    when 'Map Tier'
      result.tier = parseInt(prop.values[0][0])

  return null

stripSetText = (input) ->
  input.replace(/(<<set:MS>><<set:M>><<set:S>>|Superior\s+)/g, '').trim()

parseType = (item, result) ->
  frame =
    switch item.frameType
      when 0 then 'Normal'
      when 1 then 'Magic'
      when 2 then 'Rare'
      when 3 then 'Unique'
      when 4 then 'Gem'
      when 5 then 'Currency'
      when 6 then 'Divination Card'
      when 7 then 'Quest Item'
      when 8 then 'Prophecy'
      when 9 then 'Relic'
      else null

  result.name = stripSetText(item.name)
  result.typeLine = stripSetText(item.typeLine)
  result.baseLine = baseTypes[item.typeLine]

  # Normal, Magic, Rare, Unique, Relic
  if item.frameType < 4 or item.frameType is 9
    result.rarity = frame
    result.fullName = stripSetText("#{result.name} #{item.typeLine}")
    result.itemType =
      switch
        when regexes.type.weapon.test(item.typeLine) then 'Weapon'
        when regexes.type.armour.test(item.typeLine) then 'Armour'
        when regexes.type.accessory.test(item.typeLine) then 'Accessory'
        when regexes.type.map.test(item.descrText) then 'Map'
        when regexes.type.jewel.test(item.descrText) then 'Jewel'
        when regexes.type.flask.test(item.descrText) then 'Flask'
        when regexes.type.leaguestone.test(item.descrText) then 'Leaguestone'
        else 'Gear'
  else if frame?
    result.itemType = frame
  else
    result.itemType = 'Unknown'

  switch result.itemType
    # todo: handle jewelry
    when 'Weapon', 'Armour', 'Accessory'
      result.gearType = item.typeLine.split(' ')[-1]

  return null

parseRequirements = (item, result) ->
  for req in item.requirements
    parsed =
      name: req.name
      value: parseInt(req.values[0][0])

    parsed.name = parsed.name.substring(0, 3).toLowerCase() if ['Intelligence', 'Strength', 'Dexterity'].indexOf(parsed.name) > 0
    result.requirements[parsed.name] = parsed.value

  return null

parseSockets = (item, result) ->
  sockets = {
    red: null
    green: null
    blue: null
    white: null
    links: []
  }

  # logic for restructuring the socket/link count data
  group = 0
  linkCount = 0
  for socket in item.sockets
    # codes based on stat names Str Dex Int ... Global???
    switch (socket.attr)
      when 'S' then sockets.red++
      when 'D' then sockets.green++
      when 'I' then sockets.blue++
      when 'G' then sockets.white++

    if socket.group is group and linkCount isnt 6
    then linkCount++
    else if linkCount > 1
      sockets.links.push (i for i in [(group + 1) .. linkCount * (group + 1)])
      linkCount = 1

  result.sockets = sockets

  return null

parsePseudos = (mod, result) ->
  damage = result.offense.damage
  defense = result.defense
  averageDps = (damage) -> ((damage.min + damage.max) / 2.0) * (1 + damage.percent)

  totals =
    armour: defense.armour.flat * (1 + defense.armour.percent)
    evasion: defense.evasion.flat * (1 + defense.armour.percent)
    shield: defense.shield.flat * (1 + defense.shield.percent)
    resist:
      all: 0.0
      maximum: defense.resist.maximum.all +
        defense.resist.maximum.fire +
        defense.resist.maximum.cold +
        defense.resist.maximum.lightning
      chaos: defense.resist.chaos
      elemental: defense.resist.elemental.all +
        defense.resist.elemental.fire +
        defense.resist.elemental.cold +
        defense.resist.elemental.lightning
    damagePerSecond:
      physical: averageDps(damage.physical)
      chaos: averageDps(damage.chaos)
      elemental: averageDps(damage.elemental.all) + averageDps(damage.elemental.cold) + averageDps(damage.elemental.lightning) + averageDps(damage.elemental.fire)
      all: 0.0

  totals.resist.all = defense.resist.elemental.all +
    defense.resist.elemental.fire +
    defense.resist.elemental.cold +
    defense.resist.elemental.lightning +
    defense.resist.chaos

  totals.damagePerSecond.all = totals.damagePerSecond.physical +
    totals.damagePerSecond.chaos +
    totals.damagePerSecond.elemental

  result.pseudo = totals

  return null

parseItem = (item) ->
  timestamp = moment().toDate()
  result =
    id: item.id
    league: item.league
    stash:
      id: item.stash
      x: item.x
      y: item.y
    size:
      width: item.w
      height: item.h
    # the name of the item, scrub the oddball prefix
    name: null
    # the full name (e.g. Rare affixes)
    fullName: null
    itemType: null
    gearType: null
    baseLine: null
    # Normal, Magic, Rare, Unique if applicable
    rarity: null
    icon: null
    iconVersion: null
    note: item.note
    identified: item.identified
    corrupted: item.corrupted
    requirements:
      level: 0
      int: 0
      dex: 0
      str: 0
    tier: null
    level: null
    quality: 0
    stack:
      count: null
      maximum: null
    price:
      raw: []
      chaos: null
    lastSeen: null
    firstSeen: timestamp
    lastParsed: timestamp
    removed: false
    flavourText: null
    attributes: []
    modifiers: []
    sockets: []
    meta:
      quality: 0
      level: item.ilvl ? 0
      prefix: false
      suffix: false
    stats:
      attribute:
        all: 0
        str: 0
        dex: 0
        int: 0
      life:
        flat: 0
        percent: 0.0
      mana:
        flat: 0
        percent: 0.0
      regen:
        life:
          flat: 0
          percent: 0.0
        mana:
          flat: 0
          percent: 0.0
      reduced:
        attributeRequirements: 0.0
        manaCost: 0.0
      lightRadius: 0.0
      movementSpeed: 0.0
      item:
        rarity: 0.0
        quantity: 0.0
    pseudo:
      resist:
        maximum: 0.0
        all: 0.0
        chaos: 0.0
        elemental: 0.0
      damagePerSecond:
        all: 0.0
        chaos: 0.0
        physical: 0.0
        elemental: 0.0
    gemLevel:
      all: 0
      aura: 0
      bow: 0
      chaos: 0
      cold: 0
      curse: 0
      elemental: 0
      fire: 0
      lightning: 0
      melee: 0
      minion: 0
      strength: 0
      spell: 0
      support: 0
      vaal: 0
    flask:
      charges: 0.0
      effect: 0.0
      chargesUsed: 0
      duration: 0.0
      recovery:
        amount: 0
        speed: 0.0
      during:
        damage:
          all: 0
          lightning: 0
        reverseKnockback: false
        stunImmunity: false
        soulEater: false
        lightRadius: 0.0
        block: 0.0
      removeAilment:
        bleeding: false
        burning: false
        freezeAndChill: false
        shock: false
    offense:
      leech:
        life:
          percent: 0.0
          elemental:
            cold: 0
            fire: 0
            lightning: 0
        mana:
          percent: 0.0
          elemental:
            cold: 0
            fire: 0
            lightning: 0
      onHit:
        life: 0
        mana: 0
        shield: 0
      onKill:
        life: 0
        mana: 0
      onCrit:
        life: 0
        mana: 0
      perTarget:
        life: 0
        shield: 0
      critical:
        global:
          chance: 0
          multiplier: 0
        elemental:
          chance: 0
          multiplier: 0
        spell:
          chance: 0
          multiplier: 0
        melee:
          chance: 0
          multiplier: 0
        dualWielding:
          chance: 0
          multiplier: 0
      ailment:
        freeze:
          chance: 0
          duration: 0
        shock:
          chance: 0
          duration: 0
        ignite:
          chance: 0
          duration: 0
      damage:
        all:
          flat: 0
          percent: 0
        projectile: 0
        areaOfEffect: 0
        spell:
          all: 0
          elemental:
            fire: 0
            cold: 0
            lightning: 0
        penetration:
          fire: 0
          cold: 0
          lightning: 0
        elemental:
          all:
            flat:
              min: 0
              max: 0
            percent: 0
          fire:
            flat:
              min: 0
              max: 0
            percent: 0
          cold:
            flat:
              min: 0
              max: 0
            percent: 0
          lightning:
            flat:
              min: 0
              max: 0
            percent: 0
        chaos:
          flat:
            min: 0
            max: 0
          percent: 0
        physical:
          flat:
            min: 0
            max: 0
          percent: 0
        conversion:
          cold:
            fire: 0
          fire:
            chaos: 0
          lightning:
            chaos: 0
            cold: 0
          physical:
            cold: 0
            fire: 0
            lightning: 0
      pierceChance: 0
      projectileSpeed: 0
      accuracyRating:
        flat: 0
        percent: 0
      attacksPerSecond: 0
      meleeRange: 0
      attackSpeed: 0
      castSpeed: 0
    defense:
      blockChance:
        spells: 0
        weapons: 0
        dualWielding: 0
      resist:
        maximum:
          fire: 0
          cold: 0
          lightning: 0
          chaos: 0
        elemental:
          fire: 0
          cold: 0
          lightning: 0
        chaos: 0
      armour:
        flat: 0
        percent: 0
      evasion:
        flat: 0
        percent: 0
      shield:
        recharge: 0
        flat: 0
        percent: 0
      prevent:
        knockedBack: false
        frozen: false
        poisoned: false
        ignited: false
    minions:
      damage: 0
      life: 0
      blockChance: 0
      movementSpeed: 0
      allResists: 0

  if item.icon?
    iconHash = qs.parse(item.icon.substring(item.icon.indexOf('?')))
    result.icon = item.icon.substring(0, item.icon.indexOf('?'))
    result.iconVersion = iconHash.v

  if item.flavourText?
    result.flavourText = item.flavourText.join('\r').replace(/\\r/, ' ')

  parseType(item, result)
  parseCurrency(item, result)

  # don't bother parsing mods for non-gear (yet)
  if item.frameType >= 4
    return result

  if item.sockets?
    parseSockets(item, result)

  if item.properties?
    for prop in item.properties
      parseProperty(prop, result)

  if item.requirements?
    parseRequirements(item, result)

  # we don't care which is which
  mods = []
  if item.implicitMods?
    Array.prototype.push.apply(mods, item.implicitMods)

  if item.explicitMods?
    Array.prototype.push.apply(mods, item.explicitMods)

  if item.utilityMods?
    Array.prototype.push.apply(mods, item.utilityMods)

  for mod in mods
    parseMod(mod, result)

  parsePseudos(mod, result)

  result

updateListing = (item, result) ->
  result.lastSeen = moment().toDate()
  parseCurrency(item, result)
  result

module.exports =
  new: parseItem
  existing: updateListing
