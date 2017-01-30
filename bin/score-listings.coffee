jsonfile = require 'jsonfile'

log = require './logging'
elastic = require './elastic'

data = jsonfile.readFileSync("#{__dirname}/../gearData.json")

valuate = (source) ->
  slug = source.match(/([+-])?([0-9\\.]+)%?/i)
  return 0 unless slug?
  parseInt(slug[2])

tokenize = (source) ->
  slug = source.replace(/([0-9]+|\+|-|%| to| increased| more| less| reduced| additional|Adds |Socketed | with| for)/g, '').replace('Spells', 'Spell').toLowerCase()
  tokens = slug.split(' ').filter (v) -> v isnt ''
  #tokens.sort()
  tokens

all = (left, right) ->
  for leftOne in left
    return false unless right.indexOf(leftOne) >= 0

  true

elastic.client.search(
  index: 'poe-listing*'
  type: 'listing'
  body:
    query:
      bool:
        must: [
          match:
            fullName: 'Woe Barb Spiraled Wand'
        ,
          match:
            removed: false
        ,
          match:
            league: 'Breach'
        ,
          match:
            rarity: 'Rare'
        ]
, (err, res) ->
  return log.as.error(err) if err?
  return unless res.hits?.hits?.length > 0

  for hit in res.hits.hits
    listing = hit._source
    console.log("examining #{listing.fullName} - #{listing.id}")
    key = listing.baseLine.toLowerCase()
    modInfo = null
    if key is 'body'
      armourType = switch
        when listing.defense.armour.flat > 0 then switch
          when listing.defense.evasion.flat > 0 and listing.defense.shield.flat > 0 then 'str_dex_int'
          when listing.defense.evasion.flat > 0 then 'str_dex'
          when listing.defense.shield.flat > 0 then 'str_int'
        when listing.defense.evasion.flat > 0 then switch
          when listing.defense.shield.flat > 0 then 'dex_int'
        when listing.defense.shield.flat > 0 then 'int'

      log.as.debug("detected #{listing.fullName} as #{armourType}")
      modInfo = data["#{armourType}_armour"]
    else
      modInfo = data[key]
    continue unless modInfo?
    totalQuality = 0
    matchedCount = 0
    for mod in listing.modifiers
      tokens = tokenize(mod)
      matchedMod = null
      for cmpKey, cmpVal of modInfo
        cmpTokens = tokenize(cmpVal.text)
        matches = all(tokens, cmpTokens)
        matchedMod = cmpVal if matches is true

      if matchedMod?
        console.log("raw input #{mod} matched #{matchedMod.text}")
        matchedCount++
        value = valuate(mod)
        quality = value / matchedMod.max
        totalQuality += quality
        console.log("roll of #{value} has quality #{quality.toFixed(4)} from #{matchedMod.min} - #{matchedMod.max}")

    if matchedCount > 0
      console.log("overall quality is #{(totalQuality / matchedCount).toFixed(4)}")
)
