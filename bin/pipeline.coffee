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
readFile = Q.denodeify(jsonfile.readFile)
writeFile = Q.denodeify(jsonfile.writeFile)
unlink = Q.denodeify(fs.unlink)
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

downloadChange = (changeId) ->
  downloaded = Q.defer()

  log.as.debug("handling the request to fetch change #{changeId}")
  duration = process.hrtime(duration)
  requestPromise(
    uri: "#{config.watcher.api.uri}?id=#{changeId}"
    gzip: true
  )
    .then (res) ->
      data = JSON.parse(res)
      downloaded.resolve()
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')

      elastic.logFetch(changeId, {
        timestamp: moment().toDate()
        fileSizeKb: res.length / 1e3
        downloadTimeMs: duration.asMilliseconds()
      })

      writeFile("#{cacheDir}/#{changeId}", {
        id: changeId
        body: data
      })

      return unless data.next_change_id?
      log.as.info("following river to #{data.next_change_id}")
      fetchChange(data.next_change_id)
    .catch(downloaded.reject)

  downloaded.promise


fetchChange = (changeId) ->
  getSize(cacheDir)
    .then (cacheSize) ->
      cacheMb = Math.round(cacheSize / 1e6)
      if cacheMb > config.watcher.cache.maxSizeMb
        log.as.debug("waiting for cache directory to be < " + config.watcher.cache.maxSizeMb + " MB - currently " + cacheMb)
        return Q.delay(changeId, cacheDelayMs).then(fetchChange)

      log.as.debug("adding a request for change #{changeId}")
      downloadLimiter.schedule(downloadChange, changeId)

handleChange = (changeId) ->
  log.as.debug("scheduling the read of #{changeId}")
  processLimiter.schedule(readChange, changeId)

readChange = (changeId) ->
  readFile("#{cacheDir}/#{changeId}")
    .then (data) -> processChange(data)

processChange = (data) ->
  if data?.error?
    log.as.error("stopped processing due to file error for #{data.id}")
    return scrubChange(data.id)

  log.as.debug("merging data for change #{data.id}")
  duration = process.hrtime()
  elastic.mergeStashes(data.body.stashes)
    .then ->
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      log.as.info("processed #{data.body.stashes.length} tabs in #{duration.asMilliseconds().toFixed(2)}ms")
    .then -> scrubChange(data.id)

scrubChange = (changeId) ->
  filePath = "#{cacheDir}/#{changeId}"
  unlink(filePath)
    .then -> touch(filePath)

findLatestChange = ->
  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        fs.statSync("#{cacheDir}/#{v}").isFile()

      items.sort (a, b) ->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

      items.pop()

watchCache = ->
  dir = path.normalize(cacheDir)
  log.as.debug("registering watch for #{dir}")
  watcher = chokidar.watch(dir, {
    depth: 0
    persistent: true
    usePolling: true
    interval: 500
    ignoreInitial: true
    awaitWriteFinish:
      pollInterval: 1000
      stabilityThreshold: 5000
  })

  eventHandler = (file) ->
    changeId = path.basename(file)
    size = fs.statSync(file)?.size
    return unless size > 0
    log.as.debug("watcher queued processing for #{changeId}")
    handleChange(changeId)

  watcher.on('add', eventHandler)
  watcher.on('change', eventHandler)
  watcher.on('error', log.as.error)

module.exports =
  startWatching: watchCache
  sync: ->
    readDir(cacheDir)
      .then (items) ->
        items = items.filter (v) ->
          info = fs.statSync("#{cacheDir}/#{v}")
          info.isFile() and info.size > 0

        tasks = []
        if items.length > 0
          tasks.push(handleChange(item)) for item in items

        Q.all(tasks)
          .catch(log.as.error)
  next: ->
    findLatestChange()
      .then(fetchChange)
