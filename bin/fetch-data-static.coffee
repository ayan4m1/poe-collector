Q = require 'q'
fs = require 'fs'
gauss = require 'gauss'
moment = require 'moment'
extend = require 'extend'
parse = require 'csv-parse'
jsonfile = require 'jsonfile'

log = require './logging'

# associated PoE game version
gameVersion = '2.6.2d'

# ideal rolls will be of this percentile
idealPercentile = 0.75

# this encompasses all "equipment"
defaultKeys = [ 2 ... 32 ]

# names of data files extracted from content.ggpk
dataFiles =
  mod: 'Mods.csv'
  modType: 'ModType.csv'
  gemTag: 'GemTags.csv'
  tag: 'Tags.csv'
  stat: 'Stats.csv'

parseCsv = Q.denodeify(parse)
readFile = Q.denodeify(fs.readFile)
writeJson = Q.denodeify(jsonfile.writeFile)

# tags that we do not care about
ignoreTypes = [
  'not_for_sale'
  'humanoid'
  'mammal_beast'
  'reptile_beast'
  'skeleton'
  'zombie'
  'ghost'
  'earth_elemental'
  'water_elemental'
  'demon'
  'necromancer_raisable'
  'lots_of_life'
  'indoors_area'
  'beach'
  'dungeon'
  'cave'
  'forest'
  'swamp'
  'mountain'
  'temple'
  'urban'
  'human'
  'beast'
  'undead'
  'construct'
  'insect'
  'undying'
  'goatman'
  'shore'
  'darkshore'
  'inland'
  'prison'
  'church'
  'sins'
  'axis'
  'cavern'
  'southernforest'
  'southernforest2'
  'forestdark'
  'weavers'
  'inca'
  'city1'
  'city2'
  'city3'
  'crematorium'
  'catacombs'
  'solaris'
  'docks'
  'barracks'
  'lunaris'
  'gardens'
  'library'
  'atziri1'
  'atziri2'
  'drops_no_mods'
  'drops_no_sockets'
  'drops_no_rares'
  'drops_no_quality'
  'drops_not_dupeable'
  'no_caster_mods'
  'no_attack_mods'
  'red_blood'
  'ghost_blood'
  'insect_blood'
  'mud_blood'
  'noblood'
  'water'
  'bones'
  'unusable_corpse'
  'undeletable_corpse'
  'hidden_monster'
  'devourer'
  'rare_minion'
  'large_model'
  'secret_area'
  'divination_card'
  'currency'
  'no_divine'
  'act_boss_area'
  'no_tempests'
  'rare'
  'breach_map'
  'breach_commander'
  'no_echo'
  'no_shroud_walker'
  'cannot_be_twinned'
  'no_bloodlines'
  'area_with_water'
  'uses_suicide_explode'
  'cannot_be_monolith'
  'no_zana_quests'
  'flask'
  'gem'
  'limited_strongbox_benefits'
  'no_monster_packs'
  'vaults_of_atziri'
  'hall_of_grandmasters'
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
    else
      'Unknown'

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
    else
      'Unknown'

handleFile = (name) ->
  readFile("#{__dirname}/../data/#{name}")
    .then (raw) ->
      parseCsv(raw, {
        from: 2
        columns: true
      })
    .catch(log.as.error)

dumpResults = (name, data) ->
  result = extend({
    createdAt: moment().toISOString()
    gameVersion: gameVersion
  }, data)

  writeJson("#{__dirname}/../data/#{name}.json", result, {
    spaces: 2
  }).catch(log.as.error)

gearData = {}
tierData = {}

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

    continue unless mod.SpawnWeightTagsKeys?.length > 2 and
    [
      'Gear'
      'Flask'
      'Master'
      'Jewel'
    ].indexOf(mapped.domain) >= 0

    tagKeys = mod.SpawnWeightTagsKeys.replace(arrayRegex, '').split(',')
    tagWeights = mod.SpawnWeightValues.replace(arrayRegex, '').split(',')

    # "or" here means if parsing failed
    clean = (v) -> parseInt(v.trim())
    tagKeys = tagKeys.map(clean)
    tagWeights = tagWeights.map(clean)

    # figure out what the net product of the weights is
    tags =
      can: []
      cannot: []

    # now we walk the keys and add to appropriate bucket
    # use a range of values (tags 2-32) to represent the "default" tag
    for i in [ 0 .. tagKeys.length - 1 ]
      key = if tagWeights[i] > 0 then 'can' else 'cannot'

      if tagKeys[i] is 0
        Array.prototype.push.apply(tags[key], defaultKeys)
      else
        tags[key].push(tagKeys[i])

    tags.net = tags.can.filter (v) -> tags.cannot.indexOf(v) is -1

    mapped.spawnWeights = tags.net.map (v) -> {
      id: v
      name: tagData[v]
    }

    for gear in mapped.spawnWeights
      continue if ignoreTypes.indexOf(gear.name) >= 0
      gearData[gear.name] = [] unless gearData[gear.name]?

      for stat in mapped.stats
        gearData[gear.name].push(stat.name) unless gearData[gear.name].indexOf(stat.name) >= 0
        tierData[stat.name] = {
          id: mapped.group
          generation: mapped.generation
          domain: mapped.domain
          text: stat.text.replace('Damage Resistance', 'Resistance')
          min: null
          max: null
          ideal: null
          tiers: []
        } unless tierData[stat.name]?

        tiers = tierData[stat.name]
        tiers.min = Math.min(tiers.min ? stat.min, stat.min)
        tiers.max = Math.max(tiers.max ? stat.max, stat.max)

        tiers.tiers.push({
          level: stat.level
          min: stat.min
          max: stat.max
          ideal: null
        }) unless tiers.tiers.findIndex((v) -> v.level is stat.level) >= 0

        continue if stat.min is stat.max
        ideal = new gauss.Vector([ stat.min ... stat.max ]).percentile(idealPercentile)
        tiers.tiers[tiers.tiers.length - 1].ideal = ideal
        tiers.ideal = Math.max(tiers.ideal ? ideal, ideal)

      gearData[gear.name].sort()

    result.push(mapped)

  Q.all([
    dumpResults('Gear', {
      types: gearData
      stats: tierData
    }),
    dumpResults('Mod', {
      results: result
    })
  ]).catch(log.as.error)
.done()
