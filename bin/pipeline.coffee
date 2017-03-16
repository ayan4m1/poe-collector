'use strict'

config = require('konfig')()

Q = require 'q'
fs = require 'fs'
path = require 'path'
touch = require 'touch'
moment = require 'moment'
jsonfile = require 'jsonfile'
Bottleneck = require 'bottleneck'
requestPromise = require 'request-promise-native'

log = require './logging'
cache = require './cache'
elastic = require './elastic'

# prevent GGG from killing our requests
downloadLimiter = new Bottleneck(
  -1   # unlimited concurrent downloads
  1000 # one second in ms
)

indexLimiter = new Bottleneck(
  config.watcher.index.concurrency
  moment.duration(config.watcher.index.interval, config.watcher.index.unit8).asMilliseconds()
)

fetchNextChange = ->
  cache.findLatest()
    .then(fetchChange)
    .catch(log.as.error)

fetchChange = (changeId) ->
  downloadLimiter.schedule(downloadChange, changeId)

downloadChange = (changeId) ->
  log.as.debug("handling the request to fetch change #{changeId}")
  duration = process.hrtime()
  requestPromise({
    uri: "#{config.watcher.stashTabUrl}?id=#{changeId}"
    gzip: true
  }).then (res) ->
    return log.as.error("HTML response from JSON endpoint") if res.startsWith("<!DOCTYPE html")
    data = JSON.parse(res)

    # timing + stats
    duration = process.hrtime(duration)
    duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
    elastic.logFetch(changeId, res.length / 1e3, duration.asMilliseconds())

    handleChange({
      id: changeId
      body: data
    }).then -> touch("#{__dirname}/../cache/#{changeId}")
      .catch(log.as.error)

    # continue on to the next data blob
    if data.next_change_id?
      log.as.info("following river to #{data.next_change_id}")
      return fetchChange(data.next_change_id)
    else
      # just retry if there is no next change ID specified
      return fetchNextChange()

handleChange = (data) ->
  handled = Q.defer()
  indexLimiter.schedule(processChange, data, handled)
  handled.promise

processChange = (data, handled) ->
  log.as.debug("process called for #{data.id}")
  elastic
    .mergeStashes(data.body.stashes)
    .catch(log.as.error)
    .then(handled)

module.exports =
  fetch: fetchNextChange
