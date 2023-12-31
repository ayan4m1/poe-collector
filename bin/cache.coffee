config = require('konfig')()

Q = require 'q'
fs = require 'fs'
touch = require 'touch'
moment = require 'moment'
requestPromise = require 'request-promise-native'

log = require './logging'

# promisified functions

mkdir = Q.denodeify(fs.mkdir)
unlink = Q.denodeify(fs.unlink)
readDir = Q.denodeify(fs.readdir)
cacheDir = "#{__dirname}/#{config.cache.cachePath}"

findLatestChangeId = () ->
  mkdir(cacheDir)
    .catch () ->
      log.as.warn("cache dir exists")
    .then(findLatestOnDisk)
    .catch (err) ->
      log.as.error(err)
      findLatestFromWeb()

findLatestOnDisk = () ->
  found = Q.defer()

  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        stats = fs.statSync("#{cacheDir}/#{v}")
        stats.isFile()

      return found.reject(new Error("no cached files")) if items.length is 0

      items.sort (a, b) ->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

      result = items.pop()
      log.as.info("resuming from cache #{result}")
      if result? then found.resolve(result) else found.reject(new Error("time sorting of files failed"))

  found.promise

findLatestFromWeb = () ->
  log.as.debug("accessing poe.ninja API to find latest change")
  requestPromise({ uri: config.cache.latestChangeUrl })
    .then (res) ->
      stats = JSON.parse(res)
      changeId = stats[config.cache.changeIdField]
      touch.sync("#{cacheDir}/#{changeId}")
      changeId

removeStaleCacheFiles = () ->
  removed = 0
  staleDate = moment().subtract(config.cache.retention.interval, config.cache.retention.unit)
  readDir(cacheDir)
    .then (items) ->
      for item in items
        cachePath = "#{cacheDir}/#{item}"
        stats = fs.statSync(cachePath)
        continue unless stats.isFile()
        created = moment(stats.birthtime)
        continue unless created.isBefore(staleDate)
        unlink(cachePath)
        removed++
      log.as.info("removed #{removed} cache files")

module.exports =
  findLatest: findLatestChangeId
  removeStale: removeStaleCacheFiles
