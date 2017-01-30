jsonfile = require 'jsonfile'

log = require './logging'
elastic = require './elastic'

data = jsonfile.readFileSync("#{__dirname}/../gearData.json")

valuate = (source) ->
  slug = source.match(/([+-])?([0-9\\.]+)%?/i)
  return 0 unless slug?
  parseInt(slug[2])

tokenize = (source) ->
  slug = source.replace(/_/g, ' ').replace(/([0-9]+|\+|-|%| to| increased| more| less| reduced| additional|Adds | additional | with| for)/g, '').replace('Spells', 'Spell').toLowerCase()
  tokens = slug.split(' ').filter (v) -> v isnt ''
  tokens

all = (left, right) ->
  for leftOne in left
    return false unless right.indexOf(leftOne) >= 0
  true

query =
  query:
    bool:
      must: [
        match:
          removed: false
      ,
        match:
          league: 'Breach'
      ,
        match:
          rarity: 'Rare'
      ]
      must_not:
        exists:
          field: 'meta.modQuality'

scoreHit = (hit) ->
  listing = hit._source
  return unless listing.baseLine?
  console.log("examining #{listing.fullName} - #{listing.baseLine}")
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
    modInfo[key] = value for key, value in data["body_armour"]
  else if key is 'map'
    key = if listing.tier > 0 and listing.tier < 6 then 'low_tier_map' else
      if listing.tier <= 10 then 'mid_tier_map' else
      if listing.tier > 10 then 'top_tier_map'
    log.as.debug("map is #{key}")
    modInfo = data[key]
  else if data[key]?
    modInfo = data[key]
    # add in weapon or jewel extra classes
  else
    log.as.warn("could not map #{key}")

  return unless modInfo?
  totalQuality = 0
  matchedCount = 0
  for mod in listing.modifiers
    tokens = tokenize(mod)
    matchedMod = null
    for cmpKey, cmpVal of modInfo
      sourceText = if cmpVal.text.trim().length > 0 then cmpVal.text else cmpKey
      cmpTokens = tokenize(sourceText)
      matches = all(tokens, cmpTokens)
      matchedMod = cmpVal if matches is true

    console.dir(mod)
    console.dir(matchedMod)
    if matchedMod?
      log.as.debug("raw input #{mod} matched #{matchedMod.text}")
      matchedCount++
      value = valuate(mod)
      quality = value / matchedMod.max
      totalQuality += quality
      log.as.debug("roll of #{value} has quality #{quality.toFixed(4)} from #{matchedMod.min} - #{matchedMod.max}")

  if matchedCount > 0
    result = totalQuality / matchedCount
    log.as.info("overall quality is #{result.toFixed(4)}")
    elastic.client.update(
      index: hit._index
      type: 'listing'
      id: hit._id
      body:
        doc:
          meta:
            modQuality: result
        doc_as_upsert: true
    , (err, res) ->
      return log.as.error(err) if err?
      console.dir(res) if res?
    )

handleSearch = (err, res) ->
  return log.as.error(err) if err?

  scoreHit(hit) for hit in res.hits.hits
  return unless res.hits.hits.length < res.hits.total
  elastic.client.scroll({
    scroll: '30s'
    scrollId: res._scroll_id
  }, handleSearch)

elastic.client.search({
  index: 'poe-listing*'
  type: 'listing'
  body: query
  scroll: '30s'
}, handleSearch)
