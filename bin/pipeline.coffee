'use strict'

config = require('konfig')()

Q = require 'q'
fs = require 'fs'
touch = require 'touch'
jsonfile = require 'jsonfile'
moment = require 'moment'
request = require 'request-promise-native'

Orchestrator = require 'orchestrator'
RateLimiter = require('limiter').RateLimiter

log = require './logging'
parser = require './parser'

baseUrl = "http://api.pathofexile.com/public-stash-tabs"
cacheDir = "#{__dirname}/../cache"

limiter = new RateLimiter(1, moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds())

stat = Q.denodeify(fs.stat)
readDir = Q.denodeify(fs.readdir)
removeFile = Q.denodeify(fs.unlink)
touchFile = Q.denodeify(touch)
readFile = Q.denodeify(jsonfile.readFile)
writeFile = Q.denodeify(jsonfile.writeFile)

exists = (path) ->
  stat(path)
    .then (info) -> info.isFile()
    .catch -> false

empty = (path) ->
  stat(path)
    .then (info) -> info['size'] is 0
    .catch -> false

recentFiles = (items, base) ->
  items = items.filter (v) ->
    fs.statSync("#{base}/#{v}").isFile()
  items.sort (a, b)->
    fs.statSync("#{base}/#{a}").mtime.getTime() - fs.statSync("#{base}/#{b}").mtime.getTime()
  items

fetchChange = (changeId) ->
  log.as.info("fetching change #{changeId}")
  url = baseUrl
  url += "?id=#{changeId}" if changeId?

  request(
    url: url
    gzip: true
  ).then (res) ->
    id: changeId
    body: JSON.parse(res)


saveChange = (data) ->
  cacheFile = "#{cacheDir}/#{data.id}"
  writeFile(cacheFile, data.body)
    .then -> log.as.info("saved document for entry #{data.id}")
    .catch(log.as.error)

processBacklog = ->
  readDir(cacheDir)
    .then (items) ->
      tasks = []
      items = recentFiles(items, cacheDir)
      if items.length > 0
        tasks.push(processChange(item)) for item in items

      log.as.info("added #{items.length} cached files to the processing queue")
      Q.all(tasks)
    .then ->
      log.as.info("finished processing backlog")
    .catch(log.as.error)

processChange = (changeId) ->
  limiter.removeTokens(1, ->
    cacheFile = "#{cacheDir}/#{changeId}"
    stat(cacheFile)
      .then (info) ->
        return unless info.isFile()
        opened =
          if info['size'] is 0
          then fetchChange(changeId)
          else readFile(cacheFile).then (data) -> { id: changeId, body: data }

        opened
          .then (data) ->
            return unless data.body?

            parser.merge(data.body)

            removeFile(cacheFile)
              .then(touchFile(cacheFile))
          .catch(log.as.error)
  )

# returns a promise to retreive the next change ID based on the current change ID
fetchNextChange = (changeId) ->
  Q.delay(moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds())
    .then(fetchChange(changeId))
    .then(saveChange)

orchestrator = new Orchestrator()

orchestrator.add('fetchNextChange', fetchNextChange)
orchestrator.add('processBacklog', processBacklog)

module.exports = {
  orchestrator: orchestrator
}
