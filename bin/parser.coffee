'use strict'

moment = require 'moment'
process = require 'process'

elastic = require './elastic'
timing = require './timing'
log = require './logging'

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
  exalt: /^Ex(alted)?(Orb)?$/i
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

parseCurrency = (item, result) ->
  result.price =
    if item.note? then item.note.match(/\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/)
    else if item.stashName? then item.stashName.match(/\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/)

  return unless result.price?.length > 0
  factor = 0
  quantity = 0
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

parseProperty = (prop, result) ->
  switch
    when /[One|Two] Handed/.test(prop.name)
      result.gearType = prop.name
    when prop.name is 'Physical Damage'
      range = prop.values[0][0].match(/(\d+)-(\d+)/)
      result.offense.physical =
        min: parseInt(range[0])
        max: parseInt(range[1])
    when prop.name is 'Chaos Damage'
      range = prop.values[0][0].match(/(\d+)-(\d+)/)
      result.offense.chaos =
        min: parseInt(range[0])
        max: parseInt(range[1])
    when prop.name is 'Elemental Damage'
      result.offense.elemental =
        fire:
          min: 0
          max: 0
        lightning:
          min: 0
          max: 0
        cold:
          min: 0
          max: 0
    when prop.name is 'Stack Size'
      stackInfo = prop.values[0][0].split(/\//)
      result.stack =
        count: stackInfo[0]
        maximum: stackInfo[1]
    when prop.name is 'Map Tier'
      result.tier = parseInt(prop.values[0][0])

parseType = (item, result) ->
  frame =
    switch (item.frameType)
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

  if item.frameType < 4
    result.rarity = frame
  else if frame?
    result.itemLine = frame
  else
    result.itemLine =
      switch
        when /^Travel to this Map by using it in the Eternal Laboratory/.text(item.descrText) then 'Map'
        when /^Place into an allocated Jewel Socket/.test(item.descrText) then 'Jewel'
        when /^Right click to drink/.test(item.descrText) then 'Flask'
        else 'Gear'

  result.baseLine

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
  result =
    id: item.id
    league: item.league
    stash: item.stash
    x: item.x
    y: item.y
    width: item.w
    height: item.h
    # the name of the item
    name: item.name
    # the full name (e.g. Rare affixes)
    fullName: item.typeLine
    # a string for all items (e.g. "Map" or "Gear")
    itemType: null
    # a string which describes gear (e.g. "Amulet")
    gearType: null
    # the "base item" for gear
    baseLine: null
    # Normal, Magic, Rare, Unique if applicable
    rarity: null
    icon: item.icon
    note: item.note
    level: item.ilvl
    locked: item.lockedToCharacter
    identified: item.identified
    corrupted: item.corrupted
    verified: item.verified
    requirements: []
    attributes: []
    modifiers: []
    sockets: []
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
    chaosPrice: 0
    removed: false
    firstSeen: moment().toDate()

  parseType(item, result)
  parseCurrency(item, result)

  if item.sockets?
    parseSockets(item, result)

  if item.properties?
    for prop in item.properties
      parseProperty(prop, result)

  if item.requirements?
    for req in item.requirements
      result.requirements.push
        name: req.name
        value: parseInt(req.values[0][0])
        hidden: req.displayMode is 0

  if item.explicitMods?
    for mod in item.explicitMods
      result.modifiers.push mod

  result

parseStash = (stash) ->
  id: stash.id
  name: stash.stash
  lastSeen: moment().toDate()
  owner:
    account: stash.accountName
    character: stash.lastCharacterName

module.exports =
  stash: parseStash
  listing: parseItem
