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

recentFiles = (items, base) ->
  items = items.filter (v) ->
    fs.statSync("#{base}/#{v}").isFile()
  items.sort (a, b)->
    fs.statSync("#{base}/#{a}").mtime.getTime() - fs.statSync("#{base}/#{b}").mtime.getTime()
  items

fetchChange = (changeId) ->
  fetched = Q.defer()

  limiter.removeTokens(1, ->
    log.as.info("fetching change #{changeId}")
    url = baseUrl
    url += "?id=#{changeId}" if changeId?

    request(
      url: url
      gzip: true
    ).then (res) -> writeFile("#{cacheDir}/#{changeId}", JSON.parse(res))
    .catch(fetched.reject)
  )

  fetched.promise

mostRecent = ->
  readDir(cacheDir)
  .then (items) -> recentFiles(items, cacheDir)

processBacklog = ->
  mostRecent()
  .then (items) ->
      tasks = []
      if items.length > 0
        tasks.push(processChange(item)) for item in items

      log.as.info("added #{items.length} cached files to the processing queue")
      Q.all(tasks)
  .then -> log.as.info("finished processing backlog")
  .catch(log.as.error)

processChange = (changeId) ->
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
          parser.merge(data.body) if data.body?

          return unless data.body.next_change_id?
          touchFile("#{cacheDir}/#{data.body.next_change_id}")
            .then(removeFile(cacheFile))
        .catch(log.as.error)

fetchNextChange = ->
  mostRecent()
    .then(processChange)
    .then(fetchNextChange)

orchestrator = new Orchestrator()

orchestrator.add('processBacklog', [], processBacklog)
orchestrator.add('fetchNextChange', ['processBacklog'], fetchNextChange)

module.exports = {
  orchestrator: orchestrator
}
