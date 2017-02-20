Q = require 'q'
cheerio = require 'cheerio'
request = require 'request-promise-native'
jsonfile = require 'jsonfile'

baseUrl = 'https://www.pathofexile.com/item-data'

affixes = {}

process = ($) ->
  types = $('.layoutBoxFull').find('h1').map (i, v) -> $(v).text()
  affixes[type] = [] for type in types

  $('table.itemDataTable tr').each (i, v) ->
    type = $(v).parents('.layoutBoxFull').find('h1').text()
    cells = $(v).children()
    return if $(cells[0]).text() is 'Name'
    names = $(cells[2]).html().split('<br>')
    vals = $(cells[3]).html().split(/<br>| to /)

    affix =
      name: $(cells[0]).text()
      level: parseInt($(cells[1]).text())
      stats: [
        names[0]
      ]
      values:
        min: parseInt(vals[0])
        max: parseInt(vals[1])

    if names.length is 2 and vals.length is 4
      affix.stats.push(names[1])
      affix.values =
        min: parseInt(vals[2])
        max: parseInt(vals[3])

    affixes[type].push affix

Q.spread([
  request("#{baseUrl}/prefixmod")
  request("#{baseUrl}/suffixmod")
],
  (prefixes, suffixes) ->
    $pre = cheerio.load prefixes
    $post = cheerio.load suffixes

    process($pre)
    process($post)

    jsonfile.writeFileSync("#{__dirname}/../data/affixes.json", affixes)

    bucket = {}
    list = {
      prefix: []
      suffix: []
    }

    for gear, mods of affixes
      for mod in mods
        for stat in mod.stats
          name = stat.replace('Local ', '').replace('Minimum ', '').replace('Maximum', '').replace('Global ').replace('Permyriad', '').trim().replace(/\s{2,}/, ' ')
          bucket[name] = if bucket[name]? then {
            min: Math.min(bucket[name].min, mod.values[0].min)
            max: Math.max(bucket[name].max, mod.values[0].max)
          } else mod.values[0]

    for key of bucket
      console.log("#{key},#{bucket[key].min},#{bucket[key].max}")

    jsonfile.writeFileSync('affix-ranges.json', bucket)

    list.prefix.sort(String.prototype.localeCompare)
    list.suffix.sort(String.prototype.localeCompare)

    jsonfile.writeFileSync('affix-names.json', list)
).catch(console.error)
