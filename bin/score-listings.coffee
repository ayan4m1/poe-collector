config = require('konfig')()

extend = require 'extend'
jsonfile = require 'jsonfile'

log = require './logging'
elastic = require './elastic'

data = jsonfile.readFileSync("#{__dirname}/../gearData.json")

utilityFlasks = [
  'Quicksilver'
  'Bismuth'
  'Stibnite'
  'Amethyst'
  'Ruby'
  'Sapphire'
  'Topaz'
  'Silver'
  'Aquamarine'
  'Granite'
  'Jade'
  'Quartz'
  'Sulphur'
  'Basalt'
]

valueRegex = /([+-])?([0-9\\.]+)%?( to ([+-])?([0-9\\.]+)%?)?/i
valuate = (source) ->
  slug = source.match(valueRegex)
  return 0 unless slug?
  if slug[5]?
    min: parseInt(slug[2])
    max: parseInt(slug[5])
  else parseInt(slug[2])

stripRegex = /\s+(to |increase(d)?|more|less|reduced|goes to|found|while you havent|when not|permyriad|of socketed|on enemies)/g
startRegex = /^(display|base|local|global|self|additional)/gi
replacements = [
  [/ spells$/i, ' spell']
  ['Velocity', 'speed']
  [/attacks/i, 'attack']
  ['to return to', 'reflects']
  [/^adds /i, 'added']
  [/\+?%$/, 'percent']
  [/\s\+$/, 'flat']
  ['Rarity of Items found', 'Item Rarity']
  ['all Elemental Resistances', 'Resist all Elements']
  ['Stun and Block', 'Stun Block']
  ['Elemental Damage with Weapons', 'Weapon Elemental Damage']
]

tokenize = (source) ->
  slug = source
    .replace(/_+/g, ' ')
    .trim()
    .toLowerCase()
    .replace(startRegex, '')
    .replace(valueRegex, '')
    .replace(stripRegex, ' ')
    .trim()

  for replacement in replacements
    slug = String.prototype.replace.apply(slug, replacement)

  tokens = slug.split(' ').filter (v) -> v isnt ''
  #log.as.debug("#{source} -> #{slug} -> #{tokens}")

  tokens

all = (left, right) ->
  for leftOne in left
    return false unless right.indexOf(leftOne) >= 0
  true

scoreHit = (hit) ->
  listing = hit._source
  return unless listing.baseLine?
  log.as.debug("examining #{listing.fullName} - #{listing.baseLine}")
  key = listing.baseLine.toLowerCase()
  modInfo = null

  if key is 'body'
    armourType = switch
      when listing.defense.armour.flat > 0 and listing.defense.evasion.flat > 0 and listing.defense.shield.flat > 0 then 'str_dex_int'
      when listing.defense.armour.flat > 0 and listing.defense.evasion.flat > 0 then 'str_dex'
      when listing.defense.armour.flat > 0 and listing.defense.shield.flat > 0 then 'str_int'
      when listing.defense.armour.flat > 0 then 'str'
      when listing.defense.evasion.flat > 0 and listing.defense.shield.flat > 0 then 'dex_int'
      when listing.defense.evasion.flat > 0 then 'dex'
      when listing.defense.shield.flat > 0 then 'int'

    log.as.debug("detected #{listing.fullName} as #{armourType}")
    modInfo = data["#{armourType}_armour"]
    extend(modInfo, data['body_armour'])
  else if key is 'map'
    key = if listing.tier > 0 and listing.tier < 6 then 'low_tier_map' else
      if listing.tier <= 10 then 'mid_tier_map' else
      if listing.tier > 10 then 'top_tier_map'
    log.as.debug("map table is #{key}")
    modInfo = data[key]
  else if key is 'flask'
    tokens = listing.baseLine.trim().split(/\s+/g)
    modInfo = {}
    # handles Life Mana and Hybrid (they have sizes as a first token)
    if tokens[1]?
      extend(modInfo, data["#{tokens[1].toLowerCase()}_flask"])

    # handles special flasks by baseLine
    extend(modInfo, data['utility_flask']) if utilityFlasks.indexOf(tokens[0]) >= 0
    extend(modInfo, data['critical_utility_flask']) if listing.baseLine.trim() is 'Diamond Flask'
  else if key is 'jewel'
    modInfo = data['jewel']
    type = switch listing.baseLine.substr(0, listing.baseLine.indexOf(' '))
      when 'Crimson' then 'str'
      when 'Cobalt' then 'int'
      when 'Viridian' then 'dex'
      else null

    if type?
      # this is how they handle jewel mods...
      extend(modInfo, data["#{type}jewel"])
      if type is 'str'
        extend(modInfo, data['not_dex'])
        extend(modInfo, data['not_int'])
      else if type is 'dex'
        extend(modInfo, data['not_int'])
        extend(modInfo, data['not_str'])
      else if type is 'int'
        extend(modInfo, data['not_str'])
        extend(modInfo, data['not_dex'])
  else if key is 'mace' and listing.baseLine.endsWith('Sceptre')
    modInfo = data['weapon']
    extend(modInfo, data['sceptre'])
  else if key is 'shield' and listing.baseLine.endsWith('Spirit Shield')
    modInfo = data['shield']
    extend(modInfo, data['focus'])
  else if key is 'sword' and (
    (listing.baseLine.endsWith('Rapier') or listing.baseLine.endsWith('Foil')) or
    ['Courtesan Sword', 'Dragoon Sword', 'Rusted Spike', 'Estoc', 'Pecoraro'].indexOf(listing.baseLine) >= 0
  )
    modInfo = data['sword']
    extend(modInfo, data['rapier'])
  else if key is 'bow' or key is 'quiver'
    modInfo = data[key]
    extend(modInfo, data['ranged'])
  else if data[key]?
    modInfo = data[key]
  else
    log.as.warn("could not find mod table for #{key}")

  return unless modInfo?

  # exception for Magic quality gear, need to BREAK here
  if listing.rarity is 'Magic'
    extend(modInfo, data['magic'])

  # add armour-specific tags
  # todo: do shields belong?
  if ['body', 'boots', 'helmet', 'gloves'].indexOf(key) >= 0
    extend(modInfo, data['armour'])

  # add weapon-specific tags
  if ['wand', 'claw', 'dagger'].indexOf(key) >= 0
    extend(modInfo, data['one_hand_weapon'])
  else if key is 'staff'
    extend(modInfo, data['two_hand_weapon'])
  else if ['axe', 'mace', 'sword'].indexOf(key) >= 0
    area = listing.width * listing.height
    type = switch area
      when 3, 4, 6 then 'one'
      when 8 then 'two'

    extend(modInfo, data["#{type}_hand_weapon"])

  # todo: what is "caster"

  totalQuality = 0
  matchedCount = 0

  for mod in listing.modifiers
    value = valuate(mod)
    continue unless value.max? or value > 0

    pair = if mod.endsWith('Resistances')
    then mod.match(/(Fire|Lightning|Cold) and (Fire|Lightning|Cold)/)
    else if mod.indexOf(' and ') > 0 and
      mod.endsWith('Strength') or mod.endsWith('Dexterity') or mod.endsWith('Intelligence')
    then mod.match(/(Strength|Dexterity|Intelligence) and (Strength|Dexterity|Intelligence)/)

    log.as.debug(mod)
    tokens = tokenize(mod)
    tokens.push(pair[1].toLowerCase(), pair[2].toLowerCase()) if pair?
    matchedMod = null
    for cmpKey, cmpVal of modInfo
      cmpTokens = tokenize(cmpKey)
      matches = all(tokens, cmpTokens)
      matchedMod = cmpVal if matches is true

    if matchedMod?
      log.as.debug("modifier #{mod} matched #{matchedMod.text}")
      matchedCount++
      if value.min? and value.max?
        quality = (value.min / matchedMod.max) + (value.max / matchedMod.max)
        display = "#{value.min} to #{value.max}"
      else
        quality = value / matchedMod.max
        display = value

      totalQuality += quality
      log.as.debug("roll of #{display} has quality #{quality.toFixed(4)} from #{matchedMod.min} - #{matchedMod.max}")
    else
      log.as.warn("could not match mod for #{mod}, tokenized as #{tokens}")

    return log.as.info("ignoring #{listing.id} as it has no mods...") unless matchedCount > 0
    result = totalQuality / matchedCount
    log.as.info("overall quality is #{result.toFixed(4)}")
    elastic.client.update({
      index: hit._index
      type: 'listing'
      id: hit._id
      body:
        script: "ctx._source.meta.modQuality = #{result}"
        upsert:
          meta:
            modQuality: 0
    }, (err, res) ->
      return log.as.error(err) if err?
      if res.result is 'updated'
        commitCount++
    )

hitCount = 0
commitCount = 0

handleSearch = (err, res) ->
  return log.as.error(err) if err?

  log.as.info("processing #{res.hits.hits.length} hits")
  scoreHit(hit) for hit in res.hits.hits
  hitCount += res.hits.hits.length

  return log.as.info("completed!") unless hitCount < res.hits.total
  log.as.info("#{((hitCount / res.hits.total) * 100).toFixed(2)}% complete, #{((commitCount / res.hits.total) * 100).toFixed(2)}% committed (#{commitCount} / #{hitCount} of #{res.hits.total})")

  elastic.client.scroll({
    scroll: '1m'
    scrollId: res._scroll_id
  }, handleSearch)

elastic.client.search({
  index: 'poe-listing*'
  type: 'listing'
  scroll: '1m'
  size: 100
  body: config.query.scoring
}, handleSearch)
