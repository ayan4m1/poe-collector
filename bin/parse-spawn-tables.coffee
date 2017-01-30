Q = require 'q'
fs = require 'fs'
parse = require 'csv-parse'
jsonfile = require 'jsonfile'

log = require './logging'

dataFiles =
  mod: 'Mods.csv'
  modType: 'ModType.csv'
  gemTag: 'GemTags.csv'
  tag: 'Tags.csv'
  stat: 'Stats.csv'

parseCsv = Q.denodeify(parse)
readFile = Q.denodeify(fs.readFile)

ignoreTypes = [
  'divination_card'
  'fishing_rod'
  'focus'
  'gem'
  'large_model'
  'limited_strongbox_benefits'
  'lots_of_life'
  'low_tier_map'
  'mid_tier_map'
  'not_dex'
  'not_int'
  'not_str'
  'old_map'
  'secret_area'
  'top_tier_map'
]

getDomain = (val) ->
  switch parseInt(val)
    when 1 then 'Gear'
    when 2 then 'Flask'
    when 3 then 'Monster'
    when 4 then 'Strongbox'
    when 5 then 'Map'
    when 9 then 'Stance'
    when 10 then 'Master'
    when 11 then 'Jewel'
    when 12 then 'Sextant'
    else 'Unknown'

getGeneration = (val) ->
  switch parseInt(val)
    when 1 then 'Prefix'
    when 2 then 'Suffix'
    when 3 then 'Unique'
    when 4 then 'Nemesis'
    when 5 then 'Corrupted'
    when 6 then 'Bloodlines'
    when 7 then 'Torment'
    when 8 then 'Tempest'
    when 9 then 'Talisman'
    when 10 then 'Enchantment'
    else 'Unknown'

handleFile = (name) ->
  readFile("#{__dirname}/../data/#{name}")
    .then (raw) ->
      parseCsv(raw, {
        from: 2
        columns: true
      })

gearData = {}

arrayRegex = /[\[\]]/g
Q.spread [
  handleFile(dataFiles.mod)
  handleFile(dataFiles.modType)
  handleFile(dataFiles.tag)
  handleFile(dataFiles.stat)
], (mods, modTypes, tags, stats) ->
  result = []

  tagData = tags.reduce((accum, curr) ->
    accum[curr.Rows] = curr.Id
    accum
  , {})

  statData = stats.reduce((accum, curr) ->
    accum[curr.Rows] = {
      name: curr.Id
      text: curr.Text
    }
    accum
  , {})

  for mod in mods
    mapped =
      name: mod.Id
      group: mod.CorrectGroup
      domain: getDomain(mod.Domain)
      generation: getGeneration(mod.GenerationType)
      stats: []
      tags: []
      spawnWeights: []

    #groups[mapped.domain] = [] unless groups[mapped.domain]?
    #groups[mapped.domain].push(mapped.group) unless groups[mapped.domain].indexOf(mapped.group) >= 0

    for i in [ 1 .. 5 ]
      key = "Stat#{i} (Stats.dat Row)"
      minKey = "Stat#{i}Min"
      maxKey = "Stat#{i}Max"
      continue unless statData[mod[key]]?
      mapped.stats.push
        id: mod[key]
        name: statData[mod[key]].name
        text: statData[mod[key]].text
        level: parseInt(mod.Level)
        min: parseInt(mod[minKey])
        max: parseInt(mod[maxKey])

    continue unless mod.SpawnWeightTagsKeys?.length > 0

    tagKeys = mod.SpawnWeightTagsKeys.replace(arrayRegex, '').split(',')
    tagWeights = mod.SpawnWeightValues.replace(arrayRegex, '').split(',')
    tagKeys = tagKeys.filter (v) -> parseInt(v.trim()) > 0

    mapped.tags = tagKeys.filter (v, i) -> parseInt(tagWeights[i].trim()) is 0
    mapped.tags = mapped.tags.map (v) ->
      return 'Unknown' unless tagData[v.trim()]?
      tagData[v.trim()].name

    mapped.spawnWeights = tagKeys.map (v, i) ->
      id = parseInt(v.trim())

      {
        id: id
        name: tagData[id]
        weight: parseInt(tagWeights[i].trim())
      }

    for gear in mapped.spawnWeights
      continue if ignoreTypes.indexOf(gear.name) >= 0
      continue unless gear.weight > 0
      exists = gearData[gear.name]?
      gearData[gear.name] = {} unless exists

      for stat in mapped.stats
        statExists = gearData[gear.name][stat.name]?
        gearData[gear.name][stat.name] = {
          text: stat.text.replace(/(Local |Global |Base )/g, '')
          min: Math.abs(stat.min)
          max: Math.abs(stat.max)
        } unless statExists
        info = gearData[gear.name][stat.name]
        if stat.min < 0 and stat.max < 0
          tempMax = stat.max
          stat.max = Math.abs(stat.min)
          stat.min = Math.abs(tempMax)
        gearData[gear.name][stat.name].min = Math.min(info.min, stat.min)
        gearData[gear.name][stat.name].max = Math.max(info.max, stat.max)

      result.push(mapped)

  jsonfile.writeFileSync('gearData.json', gearData)
  #log.as.info("parsed #{mods.length} mods")
.catch(log.as.error)
