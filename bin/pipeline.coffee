'use strict'

config = require('konfig')()

Q = require 'q'
fs = require 'fs'
path = require 'path'
touch = require 'touch'
moment = require 'moment'
chokidar = require 'chokidar'
jsonfile = require 'jsonfile'
Bottleneck = require 'bottleneck'
requestPromise = require 'request-promise-native'

log = require './logging'
elastic = require './elastic'

cacheDir = "#{__dirname}/../cache"
apiUrl = 'http://api.pathofexile.com/public-stash-tabs'
latestChangeUrl = 'http://poeninja.azureedge.net/api/Data/GetStats'

# promisified functions
readDir = Q.denodeify(fs.readdir)

# prevent GGG from killing our requests
downloadLimiter = new Bottleneck(
  -1   # unlimited concurrent downloads
  1000 # one second in ms
)

indexLimiter = new Bottleneck(
  config.watcher.index.concurrency
  moment.duration(config.watcher.index.interval, config.watcher.index.unit8).asMilliseconds()
)

fetchChange = (changeId) ->
  downloadLimiter.schedule(downloadChange, changeId)

downloadChange = (changeId) ->
  downloading = Q.defer()

  log.as.debug("handling the request to fetch change #{changeId}")
  duration = process.hrtime()
  requestPromise(
    uri: "#{apiUrl}?id=#{changeId}"
    gzip: true
  )
    .then (res) ->
      return log.as.error("Got HTML response") if res.startsWith("<!DOCTYPE html")

      data = JSON.parse(res)
      touch("#{cacheDir}/#{changeId}")
      handleChange({
        id: changeId
        body: data
      })
        .then(downloading.resolve)
        .catch(downloading.reject)

      # timing + stats
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      elastic.logFetch(changeId, res.length / 1e3, duration.asMilliseconds())

      # continue on to the next data blob
      return downloading.promise unless data.next_change_id?
      log.as.info("following river to #{data.next_change_id}")
      fetchChange(data.next_change_id)
    .catch(log.as.error)

  downloading.promise

handleChange = (data) ->
  indexLimiter.schedule(processChange, data)

processChange = (data) ->
  path = "#{cacheDir}/#{data.id}"
  log.as.debug("process called for #{data.id}")
  elastic.mergeStashes(data.body.stashes)
    .catch(log.as.error)

findLatestChange = ->
  found = Q.defer()

  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        stats = fs.statSync("#{cacheDir}/#{v}")
        processChange(v) if stats.size > 0
        stats.isFile()

      items.sort (a, b) ->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

      result = items.pop()
      if result?
        return found.resolve(result)

      fetchLatestChangeId()
        .then (changeId) -> found.resolve(changeId)
        .catch(found.reject)

  found.promise

fetchLatestChangeId = ->
  log.as.info('empty cache dir, looking for latest change ID')
  requestPromise({ uri: latestChangeUrl })
  .then (res) ->
    stats = JSON.parse(res)
    stats.nextChangeId

module.exports =
  latest: fetchLatestChangeId
  first: findLatestChange
  next: fetchChange
