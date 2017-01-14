'use strict'

vm = require 'vm'
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
    offense: /([-+]?)(\d*\.?\d+%?) (increased|reduced|more|less) (Cold |Fire |Lightning )?(Global Critical Strike Multiplier|Global Critical Strike Chance|Burning|Spell|Cast|Attack|Projectile|Movement|Melee Physical|Mine|Trap|Totem) (Throwing|Laying)?\s*(Damage|Speed|Life)( with Weapons| for Spells)?/
    flatOffense: /Adds (\d+)( to (\d+))? (Chaos |Elemental |Fire |Physical |Cold |Lightning )?Damage to (Attacks|Spells)/
    block: /([-+]?)(\d*\.?\d+%?)(?: additional| to maximum) (?:Chance to Block|Block Chance)( Spells)?\s*(?:with|while)?\s*(Staves|Shields|Dual Wielding)?/
    reflect: /Reflects (\d+) to (\d+) (Cold|Fire|Lightning|Physical) Damage to( Melee)? Attackers( on Block)?/
    resist: /([-+]?)(\d+%) to ( all)?(Lightning|Cold|Fire|Chaos|Elemental) Resistance(s?)/
    attribute: /([-+]?)(\d+) to (all Attributes|Strength|Dexterity|Intelligence)( and (Dexterity|Intelligence))?/
    vitals: /([-+]?)(\d+%?) to maximum (Life|Mana|Energy Shield)/
    minions: /Minions (deal|have) [+-]?(\d+%) (Chance|increased|to) (Damage|maximum Life|Movement Speed|all Elemental Resistances)/
    gemLevel: /\+\d to Level of Socketed (Bow|Chaos|Cold|Elemental|Fire|Lightning|Melee|Minion|Spell)? Gems/
    gemEffect: /Socketed (Curse) Gems .*/

modOperators =
  increased: (a, b) -> a * (b + 1.0)
  reduced: (a, b) -> a * (1.0 - b)
  less: (a, b) -> a - b
  more: (a, b) -> a + b
  to: (a, b, sign) -> if sign is '+' then modOperators.more(a, b) else modOperators.less(a, b)

modParsers =
  defense: (mod, result) ->
    [ fullText, sign, value, op, type ] = mod
    operator = modOperators[op]
    isPercent = value.indexOf('%') > 0
    value = parseInt(modValue.replace('%', ''))
    if isNaN(value) then value = parseFloat(value)
    if isPercent then value *= 0.01

    switch type.trim()
      when 'Armour'
        result.defense.armour = operator(result.defense.armour, value, sign)
      when 'Evasion Rating'
        result.defense.evasion = operator(result.defense.evasion, value, sign)
      when 'Armour and Evasion Rating'
        result.defense.armour = operator(result.defense.armour, value, sign)
        result.defense.evasion = operator(result.defense.evasion, value, sign)
      when 'Stun and Block Recovery'
        result.defense.shield = operator(result.defense.stunRecovery, value, sign)
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
    [ sign, value, op, first, second, third, fourth, fifth, sixth ] = mod

    value = parseInt(value.replace('%', ''))
    if value.indexOf('%') > 0 then value *= 0.01
    if sign is '-' then value *= -1

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
            result.offense.damage.projectile.all = operator(result.offense.damage.projectile.all, value)
          when 'Spell'
            result.offense.damage.spell.all = operator(result.offense.damage.spell.all, value)
          when 'Melee Physical'
            result.offense.damage.physical.min = operator(result.offense.damage.physical.min, value)
            result.offense.damage.physical.max = operator(result.offense.damage.physical.max, value)
  block: (mod, result) ->
    [ sign, value, spell, weapon ] = mod
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
    [ min, max, type, melee, block ] = mod
    range =
      min: parseInt(min)
      max: parseInt(max)
    return if isNan(range.min) or isNaN(range.max)

    #switch type
    #  when 'Physical'
    #  when 'Cold', 'Fire', 'Lightning'
  resist: (mod, result) ->
    [ sign, value, all, type ] = mod
    isPercent = value.indexOf('%') > 0
    value = parseInt(value.replace('%',''))
    if isPercent then value *= 0.01

    operator = modOperators[if sign is '+' then 'more' else 'less']
    switch type
      when 'Elemental'
        result.defense.resist.elemental.all = operator(result.defense.resist.elemental.all, value)
      when 'Chaos'
        result.defense.resist.chaos = operator(result.defense.resist.chaos, value)
      when all is 'all'
        result.defense.resist.all = operator(result.defense.resist.all, value)
  attribute: (mod, result) ->
    log.as.debug('no-op attribute parse')
  vitals: (mod, result) ->
    log.as.debug('no-op vitals parse')
  gemLevel: (mod, result) ->
    log.as.debug('no-op gem level bonus parse')
  gemEffect: (mod, result) ->
    log.as.debug('no-op gem effect parse')

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

      result.gearType =
        if result.baseLine.endsWith('Bow') then 'Bow'
        else "#{hands} Handed #{weaponType} Weapon"
    when 'Level'
      result.level = parseInt(prop.values[0][0])
    when 'Quality'
      result.quality = parseInt(prop.values[0][0].replace(/[%\\+]/g, ''))
    when 'Evasion Rating'
      result.defense.evasion += parseInt(prop.values[0][0])
    when 'Energy Shield'
      result.defense.shield += parseInt(prop.values[0][0])
    when 'Armour'
      result.defense.armour += parseInt(prop.values[0][0])
    when 'Physical Damage'
      result.offense.damage.physical = parseRange(prop.values[0][0])
    when 'Chaos Damage'
      result.offense.damage.chaos = parseRange(prop.values[0][0])
    when 'Elemental Damage'
      damage = {}

      for value in prop.values
        range = parseRange(value[0])
        damageType = parseDamageType(value[1])
        damageKey = damageType.toLowerCase()
        damage[damageKey] = range

      result.offense.damage.elemental = damage
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
    metaLevel: item.ilvl
    locked: item.lockedToCharacter
    identified: item.identified
    corrupted: item.corrupted
    verified: item.verified
    attributes: []
    modifiers: []
    sockets: []
    requirements:
      level: null
      int: null
      dex: null
      str: null
    level: null
    quality: null
    stack:
      count: null
      maximum: null
    stats:
      attribute:
        all: null
        str: null
        dex: null
        int: null
      life: null
      mana: null
      regen:
        life: null
        mana: null
      attributeRequirementReduction: null
      manaCostReduction: null
      movementSpeed: null
      lightRadius: null
      itemRarity: null
      itemQuantity: null
    gemLevel:
      bow: null
      chaos: null
      cold: null
      fire: null
      any: null
      lightning: null
      melee: null
      minion: null
      spell: null
    meta:
      crafting:
        openPrefix: null
        openSuffix: null
      total:
        allResist: null
        elementalResist: null
        damagePerSecond: null
    flask:
      charges: null
      chargedUsed: null
      duration: null
      amount: null
      recovery:
        amount: null
        speed: null
      onCrit:
        charges: null
      onUse:
        removeSouls: null
      during:
        damage:
          lightning: null
        reverseKnockback: null
        stunImmunity: null
        itemQuantity: null
        itemRarity: null
        lightRadius: null
        soulEater: null
        block: null
      removeAilment:
        bleed: null
        burning: null
        chill: null
        poison: null
        shock: null
    offense:
      onKill:
        life: null
        mana: null
        damage: null
        frenzyCharge: null
      onHit:
        life: null
        mana: null
        frenzyCharge: null
      onIgnite:
        frenzyCharge: null
      onCrit:
        bleed: null
        poison: null
      perTarget:
        life: null
        shield: null
      leech:
        life: null
        mana: null
      critical:
        chance: null
        multiplier: null
        perPowerCharge: null
        elemental:
          chance: null
          multiplier: null
        spell:
          chance: null
          multiplier: null
        melee:
          chance: null
          multiplier: null
      ailment:
        freeze:
          chance: null
          duration: null
        shock:
          chance: null
          duration: null
        ignite:
          chance: null
          duration: null
      damage:
        all:
          flat: null
          percent: null
        projectile: null
        spell: null
        melee: null
        perCurse: null
        elemental:
          all:
            flat:
              min: null
              max: null
            percent: null
          fire:
            flat:
              min: null
              max: null
            percent: null
          cold:
            flat:
              min: null
              max: null
            percent: null
          lightning:
            flat:
              min: null
              max: null
            percent: null
        chaos:
          flat:
            min: null
            max: null
          percent: null
        physical:
          flat:
            min: null
            max: null
          percent: null
        against:
          nearby: null
          blinded: null
          rares: null
        conversion:
          coldToFire: null
          fireToChaos: null
          lightningToChaos: null
          lightningToCold: null
          physicalToCold: null
          physicalToFire: null
          physicalToLightning: null
      stun:
        duration: null
        thresholdReduction: null
      knockbackChance: null
      pierceChance: null
      projectileSpeed: null
      accuracyRating:
        flat: null
        percent: null
      attacksPerSecond: null
      meleeRange: null
      attackSpeed: null
      castSpeed: null
    defense:
      resist:
        all: null
        elemental:
          fire: null
          cold: null
          lightning: null
        chaos: null
      armour: null
      evasion: null
      shield: null
      blockChance:
        weapons: null
        spells: null
        whileDualWielding: null
      stunRecovery: null
      onLowLife:
        prevent:
          stun: null
      prevent:
        ailment:
          chill: null
          freeze: null
          shock: null
          ignite: null
        stun: null
      physicalDamageReduction: null
      minion:
        blockChance: null
        resist:
          elemental: null
      recentBlock:
        armour: null
      onTrap:
        shield: null
        frenzyCharge: null
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

  result.modifiers = mods
  for mod in mods
    parseMod(mod, result)

  result

module.exports =
  listing: parseItem
