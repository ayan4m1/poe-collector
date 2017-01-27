'use strict'

touch = require 'touch'
request = require 'request-promise-native'

cacheDir = "#{__dirname}/../cache"

request({ uri: "http://poeninja.azureedge.net/api/Data/GetStats" })
  .then (res) ->
    stats = JSON.parse(res)
    touch("#{cacheDir}/#{stats.nextChangeId}")
    console.log(stats.nextChangeId)
  .catch(console.error)
