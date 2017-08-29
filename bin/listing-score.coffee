config = require('konfig')()

Q = require 'q'
process = require 'process'
extend = require 'extend'
jsonfile = require 'jsonfile'

log = require './logging'
elastic = require './elastic'

gearData =jsonfile.readFileSync("#{__dirname}/../data/Gear.json")
data = gearData.types
stats = gearData.stats
utilityFlasks = jsonfile.readFileSync("#{__dirname}/../data/Flasks.json")

bodies = []
hitCount = 0
commitCount = 0
totalHits = 0

batchSize = 1000

valueRegex = /([+-])?([0-9\\.]+)%?( to ([+-])?([0-9\\.]+)%?)?/i
valuate = (source) ->
  slug = source.match(valueRegex)
  return 0 unless slug?
  if slug[5]?
    min: parseInt(slug[2])
    max: parseInt(slug[5])
  else parseInt(slug[2])

replacements = [
  [' increased ', ' ']
  ['Minions have', 'minion']
  ['Staves', 'staff']
  ['while holding a', 'while holding']
  ['Movement Speed', 'movement velocity']
  [/attacks/i, 'attack']
  ['to return to', 'reflects']
  [/^adds /i, 'added']
  [/\+?%$/, 'percent']
  [/\s\+\s$/, 'flat']
  ['Rarity of Items found', 'item found rarity']
  ['all Elemental Resistances', 'resist all elements']
  ['Stun and Block', 'stun block']
  ['Elemental Damage with Weapons', 'weapon elemental damage']
  ['Damage over Time', 'chaos damage']
  [/Resistances$/, 'resistance']
  [/(Fire|Cold|Lightning) and (Fire|Cold|Lightning)/, '']
  [/\s+(with|while wielding a)\s+(One Handed Melee|Two Handed Melee\s)?(Mace|Staff|Claw|Dagger|Wand|Axe|Sword|Weapon|Spell|Stave)s?/, '$2 $3']
  [/(Block Chance|Chance to Block)/, 'block']
  [/for each Enemy hit by your (Attack|Spell)s/, '$1']
  [/Cast Speed with (Cold|Fire|Lightning) Skills/, '$1']
]

tokenize = (source) ->
  slug = source

  for replacement in replacements
    slug = String.prototype.replace.apply(slug, replacement)

  slug = slug
    .replace(/_+/g, ' ')
    .trim()
    .toLowerCase()
    .replace(startRegex, '')
    .replace(valueRegex, '')
    .replace(stripRegex, ' ')
    .trim()

  tokens = slug.split(' ').filter (v) -> v isnt ''
  #log.as.debug("#{source} -> #{slug} -> #{tokens}")

  tokens

startRegex = /^(display|base|self|additional)/gi
stripRegex = /\s+(to |goes to|while you havent|when not|of socketed|on enemies|for )/gi

all = (left, right) ->
  for leftOne in left
    return false unless right.indexOf(leftOne) >= 0
  true

findArmourType = (listing) ->
  switch
    when listing.defense.armour.flat > 0 and listing.defense.evasion.flat > 0 and listing.defense.shield.flat > 0 then 'str_dex_int'
    when listing.defense.armour.flat > 0 and listing.defense.evasion.flat > 0 then 'str_dex'
    when listing.defense.armour.flat > 0 and listing.defense.shield.flat > 0 then 'str_int'
    when listing.defense.armour.flat > 0 then 'str'
    when listing.defense.evasion.flat > 0 and listing.defense.shield.flat > 0 then 'dex_int'
    when listing.defense.evasion.flat > 0 then 'dex'
    when listing.defense.shield.flat > 0 then 'int'

# parse the item information to determine which mods it is
# able to receive
findEligibleMods = (listing) ->
  key = listing.baseLine.toLowerCase()
  modInfo = null

  if key is 'body'
    armourType = findArmourType(listing)
    log.as.debug("detected #{listing.fullName} as #{armourType}")
    modInfo = data["#{armourType}_armour"]
    extend(modInfo, data['body_armour'])
  else if key is 'shield'
    shieldType = findArmourType(listing)
    log.as.debug("detected #{listing.fullName} as #{shieldType}")
    modInfo = data["#{shieldType}_shield"]
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
    type = switch listing.typeLine.substr(0, listing.typeLine.indexOf(' '))
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
    modInfo = data['int_shield']
    extend(modInfo, data['focus'])
  else if key is 'sword' and listing.size.width is 1 and listing.size.height is 4
    modInfo = data['sword']
    extend(modInfo, data['rapier'])
  else if key is 'bow' or key is 'quiver'
    modInfo = data[key]
    extend(modInfo, data['ranged'])
  else if data[key]?
    modInfo = data[key]
  else
    log.as.warn("could not find mod table for #{key}")

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
    area = listing.size.width * listing.size.height
    type = switch area
      when 3, 4, 6 then 'one'
      when 8 then 'two'

    extend(modInfo, data["#{type}_hand_weapon"])

  # todo: what is "caster"

  modInfo

scoreHit = (hit) ->
  listing = hit._source
  return unless listing.baseLine?

  mods = findEligibleMods(listing)
  return log.as.warn("did not find mods for #{listing.fullName}") unless mods?

  log.as.silly("found #{mods.length} eligible mods for #{listing.fullName} - #{listing.baseLine}")

  matchedGroups = []
  matchedCount = 0
  totalQuality = 0

  for mod in listing.modifiers
    value = valuate(mod)
    continue unless value.max? or value > 0

    pair = if mod.endsWith('Resistances')
    then mod.match(/(Fire|Lightning|Cold) and (Fire|Lightning|Cold)/)
    else if mod.indexOf(' and ') > 0 and mod.endsWith('Strength') or mod.endsWith('Dexterity') or mod.endsWith('Intelligence')
    then mod.match(/(Strength|Dexterity|Intelligence) and (Strength|Dexterity|Intelligence)/)

    tokens = tokenize(mod)
    tokens.push(pair[1].toLowerCase(), pair[2].toLowerCase()) if pair?
    match = null
    for cmpKey, cmpVal of mods
      cmpTokens = tokenize(cmpVal)
      matches = all(tokens, cmpTokens)
      if matches is true and matchedGroups.indexOf(cmpKey) is -1
        match = stats[cmpVal]
        break

    if match?
      if value.min? and value.max?
        if value.min < match.min or value.max > match.max
          break
        quality = ((value.min / match.min) + (value.max / match.max) / 2)
        display = "#{value.min} to #{value.max}"
      else
        if value > match.max
          break
        quality = Math.sqrt(value / (match.ideal - match.min))
        display = value
      log.as.debug("modifier #{mod} matched #{match.text}")
      matchedGroups.push(mod.id)
      matchedCount++

      totalQuality += quality
      log.as.debug("#{mod} -> #{match.id} has quality #{quality.toFixed(4)} from #{match.min} - #{match.max}")
    else
      log.as.warn("could not match mod for #{mod}, tokenized as #{tokens}")

  if matchedCount > 0
    result = totalQuality / matchedCount
    log.as.info("overall quality is #{result.toFixed(4)}")
    bodies.push({
      update:
        _index: hit._index
        _type: 'listing'
        _id: hit._id
    }, {
      script: "ctx._source.meta.quality = #{result}"
      upsert:
        meta:
          quality: 0
    })
  else
    commitCount++

handleSearch = (err, res) ->
  return log.as.error(err) if err?

  totalHits = res.hits.total if totalHits is 0

  if res?.hits?
    log.as.info("processing #{res.hits.hits.length} hits") unless res.hits.hits.length is 0
    scoreHit(hit) for hit in res.hits.hits
    hitCount += res.hits.hits.length if res.hits.hits?

  if hitCount is totalHits and commitCount < hitCount
    log.as.info("#{((hitCount / totalHits) * 100).toFixed(2)}% complete, #{((commitCount / totalHits) * 100).toFixed(2)}% committed (#{commitCount} / #{hitCount} of #{totalHits})")
    docs = bodies.splice(0, batchSize)
    elastic.client.bulk({
      body: docs
    }, (err) ->
      return log.as.error(err) if err?
      docCount = docs.length / 2
      commitCount += docCount
      log.as.debug("checked in #{docCount} documents")
    )
    return Q.delay(750).then(handleSearch)
  else if hitCount is totalHits and commitCount is hitCount
    log.as.info("completed commits")
    process.exit(0)
  else
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
