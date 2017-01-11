'use strict'

qs = require 'qs'
moment = require 'moment'
process = require 'process'
jsonfile = require 'jsonfile'

elastic = require './elastic'
timing = require './timing'
log = require './logging'

baseTypes = jsonfile.readFileSync("#{__dirname}/../itemTypes.json")

currencyRegexes =
  bauble: /(Glassblower)?'?s?Bauble/i
  chisel: /(Cartographer)?'?s?Chis(el)?/i
  gcp: /(Gemcutter'?s?)?(Prism|gpc)/i
  jewelers: /Jew(eller)?'?s?(Orb)?/i
  chrome: /Chrom(atic)?(Orb)?/i
  fuse: /(Orb)?(of)?Fus(ing|e)?/i
  transmute: /(Orb)?(of)?Trans(mut(ation|e))?/i
  chance: /(Orb)?(of)?Chance/i
  alch: /(Orb)?(of)?Alch(emy)?/i
  regal: /Regal(Orb)?/i
  aug: /Orb(of)?Augmentation/i
  exalt: /Ex(alted)?(Orb)?/i
  alt: /Alt|(Orb)?(of)?Alteration/i
  chaos: /Ch?(aos)?(Orb)?/i
  blessed: /Bless|Blessed(Orb)?/i
  divine: /Divine(Orb)?/i
  scour: /Scour|(Orb)?(of)?Scouring/i
  mirror: /Mir+(or)?(of)?(Kalandra)?/i
  regret: /(Orb)?(of)?Regret/i
  vaal: /Vaal(Orb)?/i
  eternal: /Eternal(Orb)?/i
  gold: /PerandusCoins?/i
  silver: /(Silver|Coin)+/i

currencyFactors =
  # < 1 chaos, fluctuates
  blessed: 1 / 3
  chisel: 1 / 3
  chrome: 1 / 12
  alt: 1 / 10
  fuse: 1 / 2
  alch: 1 / 2
  scour: 1 / 2
  # chaos-equivalent
  chaos: 1
  vaal: 1
  regret: 1
  regal: 1
  # > 1 chaos
  divine: 10
  exalt: 70
  # these are silly
  eternal: 10000
  mirror: 5000

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
    offense: /([-+]?)(\d*\.?\d+%?) (increased|reduced|more|less) (Spell|Cast|Attack|Projectile|Movement|Melee Physical) (Damage|Speed)/
    defense: /([-+]?)(\d*\.?\d+%?) (to|increased) (Armour|Evasion Rating|Energy Shield)/
    stun: /([-+]?)(\d*\.?\d+%?) (increased|reduced) Stun and Block Recovery/
    block: /([-+]?)(\d*\.?\d+%?) additional Chance to Block with (Staves|Axes|Maces|Swords)/
    reflect: /Reflects (\d+) to (\d+) (Cold|Fire|Lightning|Physical) Damage to( Melee)? Attackers( on Block)?/

parseMod = (mod, result) ->
  ###for type, regex of regexes.mods
    matchData = mod.match(regex)
    continue unless matchData?
    log.as.info("found mod matching type #{type}")
    return###

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
  result.price.pop()
  for term in result.price
    continue if term is 'price' or term is 'b/o'
    if isNaN(parseInt(term))
      for key, regex of currencyRegexes
        if regex.test(term)
          log.as.debug("[currency] input #{term} matched #{key}")
          factor = currencyFactors[key]
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
      result.offense.physical = parseRange(prop.values[0][0])
    when 'Chaos Damage'
      result.offense.chaos = parseRange(prop.values[0][0])
    when 'Elemental Damage'
      damage = {}

      for value in prop.values
        range = parseRange(value[0])
        damageType = parseDamageType(value[1])
        damageKey = damageType.toLowerCase()
        damage[damageKey] = range

      result.offense.elemental = damage
    when 'Critical Strike Chance'
      result.offense.critChance = parseFloat(prop.values[0][0].replace('%', ''))
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
    red: 0
    green: 0
    blue: 0
    white: 0
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
    level: null
    locked: item.lockedToCharacter
    identified: item.identified
    corrupted: item.corrupted
    verified: item.verified
    requirements:
      level: null
      int: null
      dex: null
      str: null
    attributes: []
    modifiers: []
    sockets: []
    quality: null
    stack:
      count: null
      maximum: null
    offense:
      elemental:
        fire:
          min: 0
          max: 0
        cold:
          min: 0
          max: 0
        lightning:
          min: 0
          max: 0
      chaos:
        min: 0
        max: 0
      physical:
        min: 0
        max: 0
      critChance: 0
      attacksPerSecond: 0
      meleeRange: 0
    defense:
      resistance:
        elemental:
          fire: 0
          cold: 0
          lightning: 0
        chaos: 0
      armour: 0
      evasion: 0
      shield: 0
    price: null
    chaosPrice: null
    removed: false
    firstSeen: timestamp
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
