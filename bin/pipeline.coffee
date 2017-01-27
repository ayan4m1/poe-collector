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
cacheConfig =
  delay: moment.duration(config.watcher.cache.delay.interval, config.watcher.cache.delay.unit).asMilliseconds()
  size: config.watcher.cache.maxSizeMb

# promisified functions
readDir = Q.denodeify(fs.readdir)
getSize = Q.denodeify(require('get-folder-size'))

# configurable concurrency level and scheduling interval
downloadLimiter = new Bottleneck(
  config.watcher.fetch.concurrency,
  moment.duration(config.watcher.fetch.interval, config.watcher.fetch.unit).asMilliseconds()
)

processLimiter = new Bottleneck(
  config.watcher.process.concurrency,
  moment.duration(config.watcher.process.interval, config.watcher.process.unit).asMilliseconds()
)

downloadChange = (changeId, downloaded) ->
  log.as.debug("handling the request to fetch change #{changeId}")
  duration = process.hrtime()
  requestPromise(
    uri: "http://api.pathofexile.com/public-stash-tabs?id=#{changeId}"
    gzip: true
  )
    .then (res) ->
      data = JSON.parse(res)
      touch("#{cacheDir}/#{changeId}")
      downloaded.resolve(
        id: changeId
        body: data
      )

      # timing + stats
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      elastic.logFetch(changeId, res.length / 1e3, downloadTimeMs: duration.asMilliseconds())

      # continue on to the next data blob
      return unless data.next_change_id?
      log.as.info("following river to #{data.next_change_id}")
      fetchChange(data.next_change_id)
    .catch(downloaded.reject)

fetchChange = (changeId) ->
  fetched = Q.defer()

  getSize(cacheDir)
    .catch(log.as.error)
    .then (cacheSize) ->
      cacheMb = Math.round(cacheSize / 1e6)
      if cacheMb > cacheConfig.size
        log.as.debug("waiting for cache directory to be < " + cacheConfig.size + " MB - currently " + cacheMb)
        return Q.delay(changeId, cacheConfig.delay).then(fetchChange)

      log.as.debug("adding a request for change #{changeId}")
      downloadLimiter.schedule(downloadChange, changeId, fetched)

  fetched.promise.then(processChange)

processChange = (data) ->
  processed = Q.defer()

  log.as.debug("process called for #{data.id}")
  processLimiter.schedule(elastic.mergeStashes, data.body.stashes, processed)

  processed.promise

findLatestChange = ->
  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        fs.statSync("#{cacheDir}/#{v}").isFile()

      items.sort (a, b) ->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

      items.pop()

module.exports =
  first: findLatestChange
  next: fetchChange
