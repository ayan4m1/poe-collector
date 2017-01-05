'use strict'

config = require('konfig')()

Q = require 'q'
fs = require 'fs'
touch = require 'touch'
jsonfile = require 'jsonfile'
moment = require 'moment'
request = require 'request-promise-native'

RateLimiter = require('limiter').RateLimiter

elastic = require './elastic'
log = require './logging'

baseUrl = "http://api.pathofexile.com/public-stash-tabs"
cacheDir = "#{__dirname}/../cache"

# allow one request every configured interval
limiter = new RateLimiter(1, moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds())

stat = Q.denodeify(fs.stat)
readDir = Q.denodeify(fs.readdir)
removeFile = Q.denodeify(fs.unlink)
readFile = Q.denodeify(jsonfile.readFile)
writeFile = Q.denodeify(jsonfile.writeFile)

fetchChange = (changeId) ->
  fetched = Q.defer()

  log.as.info("enqueuing a request for change #{changeId}")
  url = baseUrl
  url += "?id=#{changeId}" if changeId?

  limiter.removeTokens(1, ->
    duration = process.hrtime()
    request(
      uri: url
      gzip: true
    ).then (res) ->
      data = JSON.parse(res)
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      fetchTime = duration.asSeconds()
      sizeKb = res.length / 1e3
      log.as.info("finished fetch in #{(fetchTime * 1e3)}ms (#{(sizeKb / fetchTime).toFixed(1)} KBps)")

      writeFile("#{cacheDir}/#{changeId}", data)
        .then ->
          fetched.resolve
            id: changeId
            body: data
        .catch(fetched.reject)
      .catch(fetched.reject)
  )

  fetched.promise

processChange = (changeId) ->
  log.as.info("reading cached data for change #{changeId}")
  cacheFile = "#{cacheDir}/#{changeId}"
  readFile(cacheFile)
    .then (data) ->
      tasks = []

      tasks.push(
        elastic.mergeStashes(data.stashes)
          .then(elastic.mergeListings)
      )
      tasks.push(fetchChange(data.next_change_id)) if data.next_change_id?

      Q.all(tasks)
  .then(removeFile(cacheFile))
  .then ->
    touch.sync(cacheFile)

changeExists = (path) ->
  stat(path)
    .then (info) ->
      if info.isFile() and info['size'] > 0 then info['size'] else 0

processOrFetchChange = (changeId) ->
  cacheFile = "#{cacheDir}/#{changeId}"
  log.as.info("checking state of #{cacheFile}")
  changeExists(cacheFile)
    .then (valid) ->
      if valid <= 0 then fetchChange(changeId)
      else processChange(changeId)
    .catch(log.as.error)

findLatestChange = ->
  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        fs.statSync("#{cacheDir}/#{v}").isFile()
      items.sort (a, b)->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()
      items.pop()

module.exports =
  next: (current) ->
    getChange = if current? then current else findLatestChange
    getChange()
      .then(processOrFetchChange)
