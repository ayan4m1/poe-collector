'use strict'

Q = require 'q'
cheerio = require 'cheerio'
jsonfile = require 'jsonfile'
Bottleneck = require 'bottleneck'
requestPromise = require 'request-promise-native'
sortObjectKeys = require 'sort-object'

log = require './logging'

baseUrl = 'http://poedb.tw/us'
jsonUrl = 'json.php/item_class?cn='
uniqueUrl = 'unique.php?cn='

spamLimiter = new Bottleneck(1, 250)
mappingFile = "#{__dirname}/../data/GearTypes.json"
resultFile = "#{__dirname}/../data/BaseTypes.json"

completed = 0
types = []
result = {}
typeMappings = jsonfile.readFileSync(mappingFile)

fetchType = (url, extractor) ->
  log.as.debug("fetching #{url}")
  spamLimiter.schedule(requestPromise, url)
    .catch(log.as.error)
    .then(extractor)
    .then ->
      completed++
      log.as.info("#{((completed / parseFloat(types.length)) * 100.0).toFixed(2)}% completed (#{completed}/#{types.length})")

fetchItemTypes = () ->
  requestPromise("#{baseUrl}/item.php")
    .catch(log.as.error)
    .then (res) ->
      $ = cheerio.load(res)
      for v in $('.navbar').last().find('.dropdown-menu').find('li').find('a')
        attr = $(v).attr('href')
        continue if attr.indexOf('gem.php') >= 0
        attr = attr.substring(attr.lastIndexOf('=') + 1)
        types.push(fetchType("#{baseUrl}/#{jsonUrl}#{attr}", (res) ->
          $ = cheerio.load("")
          parsed = JSON.parse(res)
          for v in parsed.data
            $v = $(v[1])
            first = $v.eq(0).text()
            second = $v.eq(3).text()
            result[first] = typeMappings[second]
        ))

      Q.all(types)

fetchUniqueTypes = () ->
  requestPromise("#{baseUrl}/unique.php")
    .catch(log.as.error)
    .then (res) ->
      $ = cheerio.load(res)
      counter = 0
      for v in $('.navbar').last().find('.dropdown-menu').find('li').find('a')
        attr = $(v).attr('href')
        attr = attr.substring(attr.lastIndexOf('=') + 1)
        continue unless counter++ < 5
        types.push(fetchType("#{baseUrl}/#{uniqueUrl}#{attr}", (res) =>
          $ = cheerio.load(res)
          $('tbody').find('a[href]:first-child')
            .parent()
            .each (i, v) =>
              $v = $(v)
              $heading = $('h4').text()
              first = $v.contents().eq(0).text().trim()
              second = $heading.substring(0, $heading.lastIndexOf(' '))
              result[first] = typeMappings[second]
        ))

      Q.all(types)

fetches = [fetchItemTypes(), fetchUniqueTypes()]
Q.all(fetches)
  .then ->
    log.as.info("completed crawling base type lists, ended up with #{Object.keys(result).length} base types")
    console.dir(sortObjectKeys(result));
    jsonfile.writeFileSync(resultFile, sortObjectKeys(result), { spaces: 2 })
  .catch(log.as.error)
