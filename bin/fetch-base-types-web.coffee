'use strict'

Q = require 'q'
cheerio = require 'cheerio'
jsonfile = require 'jsonfile'
Bottleneck = require 'bottleneck'
requestPromise = require 'request-promise-native'
sortObjectKeys = require 'sort-object'

log = require './logging'

baseUrl = 'http://poedb.tw/us'
urlTypes = [ 'item', 'unique' ]
urlInterstitial = '.php?cn='

spamLimiter = new Bottleneck(1, 250)
mappingFile = "#{__dirname}/../data/GearTypes.json"
resultFile = "#{__dirname}/../data/BaseTypes.json"

completed = 0
types = []
result = {}
typeMappings = jsonfile.readFileSync(mappingFile)

fetchType = (url) ->
  spamLimiter.schedule(requestPromise, url)
    .catch(log.as.error)
    .then (res) ->
      $ = cheerio.load(res)
      $('tbody').find('a[href]')
        .parent()
        .each (i, v) ->
          $v = $(v)
          first = $($v.contents()[0]).text().trim()
          second = $($v.contents()[2]).text().trim()
          result[first] = typeMappings[second]
      completed++
      log.as.info("#{((completed / parseFloat(types.length)) * 100.0).toFixed(2)}% completed (#{completed}/#{types.length})")

fetchTypes = (type) ->
  url = "#{type}#{urlInterstitial}"
  requestPromise("#{baseUrl}/#{url}")
    .catch(log.as.error)
    .then (res) ->
      $ = cheerio.load(res)
      for v in $('#navbar-collapse2').find('li').find("a[href^=\"#{url}\"]")
        attr = $(v).attr('href')
        types.push(fetchType("#{baseUrl}/#{attr}"))

      log.as.info("found #{types.length} item types from #{type} list")
      Q.all(types)
        .then ->
          log.as.info("completed crawling base types list, ended up with #{Object.keys(result).length} base types")
          jsonfile.writeFileSync(resultFile, sortObjectKeys(result), { spaces: 2 })
        .catch(log.as.error)

fetchTypes(type) for type in urlTypes
