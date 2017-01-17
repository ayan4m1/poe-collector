'use strict'

config = require('konfig')()

Q = require 'q'
fs = require 'fs'
path = require 'path'
touch = require 'touch'
watch = require 'node-watch'
moment = require 'moment'
jsonfile = require 'jsonfile'
Bottleneck = require 'bottleneck'
Orchestrator = require 'orchestrator'
requestPromise = require 'request-promise-native'

log = require './logging'
elastic = require './elastic'

# todo: refactor to config
baseUrl = "http://api.pathofexile.com/public-stash-tabs"
cacheDir = "#{__dirname}/../cache"

# promisified functions
readDir = Q.denodeify(fs.readdir)
readFile = Q.denodeify(jsonfile.readFile)
writeFile = Q.denodeify(jsonfile.writeFile)
unlink = Q.denodeify(fs.unlink)

# configurable concurrency level and scheduling interval
downloadLimiter = new Bottleneck(
  config.watcher.fetch.concurrency,
  moment.duration(config.watcher.fetch.interval, config.watcher.fetch.unit).asMilliseconds()
)

processLimiter = new Bottleneck(
  config.watcher.process.concurrency,
  moment.duration(config.watcher.process.interval, config.watcher.process.unit).asMilliseconds()
)

downloadChange = (changeId, promise) ->
  log.as.debug("handling the request to fetch change #{changeId}")
  duration = process.hrtime(duration)
  requestPromise(
    uri: "#{baseUrl}?id=#{changeId}"
    gzip: true
  )
    .then (res) ->
      data = JSON.parse(res)
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      fetchTime = duration.asSeconds()
      sizeKb = res.length / 1e3
      log.as.info("fetched #{sizeKb}KB in #{(fetchTime * 1e3)}ms (#{(sizeKb / fetchTime).toFixed(1)} KBps)")

      promise.resolve
        id: changeId
        body: data
    .catch(promise.reject)

fetchChange = (changeId) ->
  fetched = Q.defer()

  log.as.debug("adding a request for change #{changeId}")
  downloadLimiter.schedule(downloadChange, changeId, fetched)

  filePath = "#{cacheDir}/#{changeId}"
  fetched.promise
    .then (data) ->
      writeFile(filePath, data)
      return unless data.body.next_change_id?
      fetchChange(data.body.next_change_id)

handleChange = (changeId) ->
  processed = Q.defer()

  filePath = "#{cacheDir}/#{changeId}"
  info = fs.statSync(filePath)
  return fetchChange(changeId) if info.size is 0

  log.as.info("processing change #{changeId}")
  readFile(filePath)
    .then (data) ->
      processLimiter.schedule(processChange, data, processed)
    .catch(log.as.error)

  processed.promise

processChange = (data) ->
  log.as.debug("merging data for change #{data.id}")
  filePath = "#{cacheDir}/#{data.id}"
  duration = process.hrtime()
  elastic.mergeStashes(data.body.stashes)
    .catch(log.as.error)
    .then (res) ->
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      log.as.info("merged #{res.listings} listings across #{res.stashes} tabs in #{duration.asMilliseconds().toFixed(2)}ms, (#{Math.floor(res.listings / duration.asSeconds())} docs/sec)")
    .then -> unlink(filePath)
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
  watcher = watch(dir)

  watcher.on('change', (file) ->
    changeId = path.basename(file)
    size = fs.statSync("#{cacheDir}/#{changeId}")?.size
    return unless size isnt 0
    log.as.debug("watcher queued processing for #{changeId}")
    handleChange(changeId)
  )

  watcher.on('error', log.as.error)

module.exports =
  startWatching: watchCache
  sync: ->
    readDir(cacheDir)
      .then (items) ->
        items = items.filter (v) ->
          info = fs.statSync("#{cacheDir}/#{v}")
          info.isFile() and info.size > 0

        return unless items.length > 0
        tasks = handleChange(item) for item in items

        Q.all(tasks)
          .catch(log.as.error)
  next: ->
    findLatestChange()
      .then(handleChange)
