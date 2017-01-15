'use strict'

qs = require 'qs'
moment = require 'moment'
process = require 'process'
jsonfile = require 'jsonfile'

currency = require './currency'
elastic = require './elastic'
timing = require './timing'
log = require './logging'

baseTypes = jsonfile.readFileSync("#{__dirname}/../itemTypes.json")

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
  mods:
    defense: /([-+]?)(\d*\.?\d+%?) (to|increased|reduced) (Armour and Evasion Rating|Armour|Evasion Rating|Stun and Block Recovery)/
    offense: /([-+]?)(\d*\.?\d+%?) (increased|reduced|more|less) (Cold |Fire |Lightning )?(Global Critical Strike Multiplier|Global Critical Strike Chance|Burning|Spell|Cast|Attack|Projectile|Movement|Elemental|Physical|Mine|Trap|Totem) (Throwing|Laying)?\s*(Damage|Speed|Life)( with Weapons| for Spells)?/
    flatOffense: /Adds (\d+)( to (\d+))? (Chaos |Elemental |Fire |Physical |Cold |Lightning )?Damage to (Attacks|Spells)/
    block: /([-+]?)(\d*\.?\d+%?)(?: additional| to maximum) (?:Chance to Block|Block Chance)( Spells)?\s*(?:with|while)?\s*(Staves|Shields|Dual Wielding)?/
    reflect: /Reflects (\d+) to (\d+) (Cold|Fire|Lightning|Physical) Damage to( Melee)? Attackers( on Block)?/
    resist: /([-+]?)(\d+%) to (all )?(Lightning|Cold|Fire|Chaos|Elemental) Resistance(s?)/
    attribute: /([-+]?)(\d+) to (all )?(Attributes|Strength|Dexterity|Intelligence)( and (Dexterity|Intelligence))?/
    vitals: /([-+]?)(\d+%?) (increased|reduced|to)(?: maximum)? (Life|Mana|Energy Shield)( Recharge Rate)?/
    minions: /Minions (deal|have) [+-]?(\d+%) (Chance|increased|to) (Damage|maximum Life|Movement Speed|all Elemental Resistances)/
    gemLevel: /\+\d to Level of Socketed (Bow|Chaos|Cold|Elemental|Fire|Lightning|Melee|Minion|Spell)? Gems/
    gemEffect: /Socketed (Curse) Gems .*/
    ailment: /(\d+%) (?: chance)(to|increased) (Shock|Ignite|Freeze)( Duration on Enemies)?/
    resistPen: /Penetrates (\d+%) (Cold|Lightning|Fire|Chaos) Resistance/
    flaskAilment: /Removes (Bleeding|Burning|Curses|Freeze and Chill|Shock) on use/

modOperators =
  increased: (a, b) -> a * (b + 1.0)
  reduced: (a, b) -> a * (1.0 - b)
  less: (a, b) -> a - b
  more: (a, b) -> a + b
  to: (a, b, sign) -> if sign is '+' then modOperators.more(a, b) else modOperators.less(a, b)

modParsers =
  resistPen: (mod, result) ->
    [ value, type ] = mod
    bucket = type.toLowerCase()
    value = parseInt(value.replace('%', '')) * 0.01
    result.offense.damage.penetration[bucket] += value
  flaskAilment: (mod, result) ->
    [ type ] = mod
    log.as.debug('no-op flask ailment parse')
  ailment: (mod, result) ->
    [ value, op, type, duration ] = mod
    bucket = type.toLowerCase()
    subBucket = if duration is ' Duration on Enemies' then 'duration' else 'chance'
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%', ''))
    if isPercent then value *= 0.01
    # "to" verb is always positive here, so hardcode sign
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
      when 'Stun and Block Recovery'
        result.defense.stunRecovery = operator(result.defense.stunRecovery, value, sign)
  flatOffense: (mod, result) ->
    [ fullText, min, bogus, max, type, target ] = mod
    type = type.trim()
    range =
      min: parseInt(min)
      max: parseInt(max)
    return if isNaN(range.min) or isNaN(range.max)

    # todo: handle pseudos
    switch type
      when 'Elemental'
        result.offense.damage.elemental.all.flat.min += range.min
        result.offense.damage.elemental.all.flat.max += range.max
      when 'Cold', 'Lightning', 'Fire'
        result.offense.damage.elemental[type.toLowerCase()].flat.min += range.min
        result.offense.damage.elemental[type.toLowerCase()].flat.max += range.max
      when 'Physical', 'Chaos'
        result.offense.damage[type.toLowerCase()].flat.min += range.min
        result.offense.damage[type.toLowerCase()].flat.max += range.max
  offense: (mod, result) ->
    [ fullText, sign, value, op, first, second, third, fourth, fifth, sixth ] = mod
    return new Error(mod) unless value?
    isPercent = value.indexOf('%')
    value = parseInt(value.replace('%', ''))
    if isPercent then value *= 0.01

    # todo: handle pseudos
    operator = modOperators[op]
    switch second
      when 'Speed'
        switch first
          when 'Attack'
            result.offense.attackSpeed = operator(result.offense.attackSpeed, value)
          when 'Cast'
            result.offense.castSpeed = operator(result.offense.castSpeed, value)
          when 'Projectile'
            result.offense.projectileSpeed = operator(result.offense.projectileSpeed, value)
          when 'Movement'
            result.stats.movementSpeed = operator(result.stats.movementSpeed, value)
      when 'Damage'
        switch first
          when 'Projectile'
            result.offense.damage.projectile = operator(result.offense.damage.projectile, value)
          when 'Spell'
            result.offense.damage.spell.all = operator(result.offense.damage.spell.all, value)
          #when 'Melee Physical'
          #  result.offense.damage.physical.min = operator(result.offense.damage.physical.min, value)
          #  result.offense.damage.physical.max = operator(result.offense.damage.physical.max, value)
          when 'Elemental'
            result.offense.damage.elemental.percent = operator(result.offense.damage.elemental.percent)
          when 'Physical'
            result.offense.damage.physical.percent = operator(result.offense.damage.physical.percent)
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
      result.defense.blockChance.whileDualWielding += value
    else
      # todo: break this out into the types
      result.defense.blockChance.weapons += value
  reflect: (mod, result) ->
    [ fullText, min, max, type, melee, block ] = mod
    range =
      min: parseInt(min)
      max: parseInt(max)
    return if isNaN(range.min) or isNaN(range.max)

    #switch type
    #  when 'Physical'
    #  when 'Cold', 'Fire', 'Lightning'
  resist: (mod, result) ->
    [ fullText, sign, value, all, type ] = mod
    return new Error(mod) unless value?
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%',''))
    if isPercent then value *= 0.01

    operator = modOperators.to
    switch type
      when 'Elemental'
        # todo: do we have an "all" or do we just add each one
        result.defense.resist.elemental.all = operator(result.defense.resist.elemental.all, value, sign)
      when 'Chaos'
        result.defense.resist.chaos = operator(result.defense.resist.chaos, value, sign)
      when all is 'all'
        result.defense.resist.all = operator(result.defense.resist.all, value, sign)
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
  gemLevel: (mod, result) ->
    log.as.debug('no-op gem level bonus parse')
  gemEffect: (mod, result) ->
    log.as.debug('no-op gem effect parse')
  minions: (mod, result) ->
    log.as.debug('no-op minions parse')

parseMod = (mod, result) ->
  for type, regex of regexes.mods
    matchData = mod.match(regex)
    continue unless matchData?
    return unless modParsers[type]?
    modParsers[type](matchData, result)
    break

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
  result.price =
    if item.note? then item.note.match(regexes.price.note)
    else if item.stashName? then item.stashName.match(regexes.price.name)

  return unless result.price?.length > 0
  factor = 0
  quantity = 0
  result.price.shift()
  for term in result.price
    continue if term is 'price' or term is 'b/o'
    if isNaN(parseInt(term))
      for key, regex of currency.regexes
        if regex.test(term)
          log.as.debug("[currency] input #{term} matched #{key}")
          factor = currency.values[key]
          break
    else quantity = parseInt(term)

  log.as.debug("[currency] factor #{factor} qty #{quantity}")
  return unless factor > 0 and quantity > 0
  result.chaosPrice = factor * quantity

parseRange = (range) ->
  results = range.match(/(\d+)-(\d+)/)

  {
    min: parseInt(results[0])
    max: parseInt(results[1])
  }

parseProperty = (prop, result) ->
  switch prop.name
    when 'One Handed', 'Two Handed'
      hands = prop.name.match(/([One|Two])/)[0]
      weaponType = if result.baseLine.endsWith('Wand') then 'Projectile' else 'Melee'
      result.gearType = "#{hands} Handed #{weaponType} Weapon"
    when 'Bow'
      result.gearType = 'Bow'
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
      result.offense.critical.chance = parseFloat(prop.values[0][0].replace('%', ''))
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
  null

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
      else null

  result.name = item.name.replace(/(<<set:MS>><<set:M>><<set:S>>|Superior\s+)/g, '')
  result.typeLine = item.typeLine
  result.baseLine = baseTypes[item.typeLine]
  # < 4 means Normal, Magic, or Rare item
  if item.frameType < 4
    result.rarity = frame
    result.fullName = "#{result.name} #{item.typeLine}"
    result.itemType =
      switch
        when regexes.type.weapon.test(item.typeLine) then 'Weapon'
        when regexes.type.armour.test(item.typeLine) then 'Armour'
        when regexes.type.accessory.test(item.typeLine) then 'Accessory'
        when regexes.type.map.test(item.descrText) then 'Map'
        when regexes.type.jewel.test(item.descrText) then 'Jewel'
        when regexes.type.flask.test(item.descrText) then 'Flask'
        else 'Gear'
  else if frame?
    result.itemType = frame
  else
    result.itemType = 'Unknown'

  switch result.itemType
    when 'Weapon', 'Armour', 'Accessory'
      result.gearType = item.typeLine.split(' ')[-1]

parseRequirements = (item, result) ->
  for req in item.requirements
    parsed =
      name: req.name
      value: parseInt(req.values[0][0])

    parsed.name = parsed.name.substring(0, 3) if ['Intelligence', 'Strength', 'Dexterity'].indexOf(parsed.name) > 0
    result.requirements[parsed.name.toLowerCase()] = parsed.value

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

parseItem = (item) ->
  timestamp = moment().toDate()
  result =
    id: item.id
    league: item.league
    stash: item.stash
    x: item.x
    y: item.y
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
    locked: item.lockedToCharacter
    identified: item.identified
    corrupted: item.corrupted
    verified: item.verified
    attributes: []
    modifiers: []
    sockets: []
    requirements:
      level: 0
      int: 0
      dex: 0
      str: 0
    level: 0
    quality: 0
    stack:
      count: 0
      maximum: 0
    stats:
      attribute:
        all: 0
        str: 0
        dex: 0
        int: 0
      life:
        flat: 0
        percent: 0
      mana:
        flat: 0
        percent: 0
      regen:
        life:
          flat: 0
          percent: 0
        mana:
          flat: 0
          percent: 0
      attributeRequirementReduction: 0
      manaCostReduction: 0
      movementSpeed: 0
      lightRadius: 0
      itemRarity: 0
      itemQuantity: 0
    gemLevel:
      bow: 0
      chaos: 0
      cold: 0
      fire: 0
      any: 0
      lightning: 0
      melee: 0
      minion: 0
      spell: 0
    meta:
      level: 0
      crafting:
        openPrefix: false
        openSuffix: false
      total:
        resistance:
          all: 0
          elemental: 0
        damagePerSecond:
          all: 0
          physical: 0
          elemental: 0
    flask:
      charges: 0
      chargedUsed: 0
      duration: 0
      recovery:
        amount: 0
        speed: 0
      onCrit:
        charges: 0
      onUse:
        removeSouls: 0
        armour: 0
      during:
        damage:
          all: 0
          lightning: 0
        reverseKnockback: false
        stunImmunity: 0
        itemQuantity: 0
        itemRarity: 0
        lightRadius: 0
        soulEater: false
        block: 0
      removeAilment:
        bleeding: 0
        burning: 0
        freezeAndChill: 0
        shock: 0
    offense:
      onKill:
        life: 0
        mana: 0
        damage: 0
        frenzyCharge: false
      onHit:
        life: 0
        mana: 0
        frenzyCharge: false
      onIgnite:
        frenzyCharge: false
      onCrit:
        bleed: false
        poison: false
      perTarget:
        life: 0
        shield: 0
      leech:
        life:
          flat: 0
          percent: 0
        mana:
          flat: 0
          percent: 0
      critical:
        chance: 0
        multiplier: 0
        perPowerCharge:
          chance: 0
        elemental:
          chance: 0
          multiplier: 0
        spell:
          chance: 0
          multiplier: 0
        melee:
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
        spell:
          all: 0
          elemental:
            fire: 0
            cold: 0
            lightning: 0
        melee: 0
        perCurse: 0
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
        against:
          nearby: 0
          blinded: 0
          rares: 0
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
      stun:
        duration: 0
        thresholdReduction: 0
      knockbackChance: 0
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
      resist:
        all: 0
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
      blockChance:
        weapons: 0
        spells: 0
        whileDualWielding: 0
      stunRecovery: 0
      physicalDamageReduction: 0
      onLowLife:
        prevent:
          stun: false
      prevent:
        ailment:
          chill: false
          freeze: false
          shock: false
          ignite: false
        stun: false
      minion:
        blockChance: 0
        resist:
          elemental:
            all: 0
      totem:
        resist:
          elemental:
            all: 0
      onRecentBlock:
        armour: 0
      onTrap:
        shield: 0
        frenzyCharge: 0
    price: null
    chaosPrice: null
    removed: false
    firstSeen: timestamp
    lastSeen: timestamp
    flavourText: null

  if item.icon?
    iconHash = qs.parse(item.icon.substring(item.icon.indexOf('?')))
    result.icon = item.icon.substring(0, item.icon.indexOf('?'))
    result.iconVersion = iconHash.v

  if item.flavourText?
    result.flavourText = item.flavourText.join('\r').replace(/\\r/, ' ')

  parseType(item, result)
  parseCurrency(item, result)

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

  for mod in mods
    parseMod(mod, result)

  result

module.exports =
  listing: parseItem
