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

# promisified functions
readDir = Q.denodeify(fs.readdir)
readJson = Q.denodeify(jsonfile.readFile)
writeJson = Q.denodeify(jsonfile.writeFile)

# prevent GGG from killing our requests
downloadLimiter = new Bottleneck(
  config.watcher.fetch.concurrency,
  moment.duration(config.watcher.fetch.interval, config.watcher.fetch.unit).asMilliseconds()
)

fetchChange = (changeId) ->
  downloadLimiter.schedule(downloadChange, changeId)

downloadChange = (changeId) ->
  log.as.debug("handling the request to fetch change #{changeId}")
  duration = process.hrtime()
  requestPromise(
    uri: "http://api.pathofexile.com/public-stash-tabs?id=#{changeId}"
    gzip: true
  )
    .then (res) ->
      data = JSON.parse(res)
      writeJson("#{cacheDir}/#{changeId}", data)

      # timing + stats
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      elastic.logFetch(changeId, res.length / 1e3, duration.asMilliseconds())

      # continue on to the next data blob
      return unless data.next_change_id?
      log.as.info("following river to #{data.next_change_id}")
      fetchChange(data.next_change_id)
    .catch(log.as.error)

processChange = (data) ->
  log.as.debug("process called for #{data.id}")
  elastic.mergeStashes(data.body.stashes)

findLatestChange = ->
  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        stats = fs.statSync("#{cacheDir}/#{v}")
        processChange(v) unless stats.size is 0
        stats.isFile()

      items.sort (a, b) ->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

      items.pop()

module.exports =
  next: fetchChange(findLatestChange())
