'use strict'

config = require('konfig')()

Q = require 'q'
fs = require 'fs'
touch = require 'touch'
jsonfile = require 'jsonfile'
moment = require 'moment'
requestPromise = require 'request-promise-native'
Bottleneck = require 'bottleneck'

elastic = require './elastic'
log = require './logging'

baseUrl = "http://api.pathofexile.com/public-stash-tabs"
cacheDir = "#{__dirname}/../cache"

# configurable concurrency level and scheduling interval
limiter = new Bottleneck(
  config.watcher.concurrency,
  moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds()
)

readDir = Q.denodeify(fs.readdir)

downloadChange = (changeId, promise) ->
  log.as.info("handling the request to fetch change #{changeId}")
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

  log.as.info("adding a request for change #{changeId}")
  limiter.schedule(downloadChange, changeId, fetched)

  fetched.promise.then(processChange)

processChange = (data) ->
  log.as.info("merging data for change #{data.id}")
  elastic.mergeStashes(data.body.stashes)
    .then(elastic.mergeListings)
    .then ->
      log.as.info("completed merge of #{data.id}")
      touch("#{cacheDir}/#{data.body.next_change_id}")
      Q(data.body.next_change_id ? data.id)

findLatestChange = ->
  readDir(cacheDir)
    .then (items) ->
      items = items.filter (v) ->
        fs.statSync("#{cacheDir}/#{v}").isFile()
      items.sort (a, b)->
        fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()
      items.pop()

module.exports =
  next: ->
    findLatestChange()
      .then(fetchChange)
