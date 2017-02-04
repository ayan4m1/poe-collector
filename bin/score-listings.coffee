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
  ['Spells', 'spell']
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
    base = listing.baseLine.trim().split(/\s+/g).pop()
    # todo: figure out the base flask mods
    modInfo = {}
    extend(modInfo, data['utility_flask']) if utilityFlasks.indexOf(base) >= 0
    extend(modInfo, data['critical_utility_flask']) if listing.baseLine.trim() is 'Diamond Flask'
  else if key is 'mace'
    modInfo = data['sceptre']
  else if key is 'shield' and listing.baseLine.endsWith('Spirit Shield')
    modInfo = data['focus']
    extend(modInfo, data['shield'])
  else if data[key]?
    modInfo = data[key]
  else
    log.as.warn("could not find mod table for #{key}")

  return unless modInfo?

  if ['body', 'boots', 'helmet', 'gloves'].indexOf(key) >= 0
    extend(modInfo, data['armour'])

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

    if matchedCount > 0
      result = totalQuality / matchedCount
      log.as.info("overall quality is #{result.toFixed(4)}")
      elastic.client.update({
        index: hit._index
        type: 'listing'
        id: hit._id
        retry_on_conflict: 5
        body:
          doc:
            meta:
              modQuality: result
          doc_as_upsert: true
      }, (err, res) ->
        return log.as.error(err) if err?
        commitCount++ if res.result is 'updated'
      )

hitCount = 0
commitCount = 0

handleSearch = (err, res) ->
  return log.as.error(err) if err?

  scoreHit(hit) for hit in res.hits.hits
  hitCount += res.hits.hits.length

  return log.as.info("completed!") unless hitCount < res.hits.total
  log.as.info("#{((hitCount / res.hits.total) * 100).toFixed(2)}% complete, #{((commitCount / res.hits.total) * 100).toFixed(2)}% committed (#{commitCount} / #{hitCount} of #{res.hits.total})")

  elastic.client.scroll({
    scroll: '30s'
    scrollId: res._scroll_id
  }, handleSearch)

elastic.client.search({
  index: 'poe-listing*'
  type: 'listing'
  scroll: '30s'
  size: 100
  body: config.query.scoring
}, handleSearch)
