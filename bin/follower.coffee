'use strict'

Q = require 'q'
fs = require 'fs'
touch = require 'touch'
jsonfile = require 'jsonfile'
request = require 'request-promise-native'

log = require './logging'

findStart = ->
  found = Q.defer()

  cacheDir = "#{__dirname}/../cache"
  log.as.debug("[follow] searching cache dir #{cacheDir}")
  fs.readdir cacheDir, (err, items) ->
    found.reject(err) if err?
    found.resolve(null) unless items?.length > 0

    # prune non-files
    items = items.filter (v) ->
      return fs.statSync("#{cacheDir}/#{v}").isFile()

    # most recent first
    items.sort (a, b) ->
      fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

    changeId = items.pop()
    log.as.info("[follow] resuming from change #{changeId}")
    found.resolve(changeId)

  found.promise

follow = (changeId) ->
  followed = Q.defer()

  # call this one of two ways based on cache state
  resolve = (data) ->
    followed.reject(data) unless data?
    followed.resolve
      data: data.stashes
      nextChange: ->
        return unless data.next_change_id?
        log.as.info("[follow] fetching changes from #{data.next_change_id}")
        follow(data.next_change_id)

  url = 'http://www.pathofexile.com/api/public-stash-tabs'
  url += "?id=#{changeId}" if changeId?

  log.as.debug("[follow] fetching #{url}")
  duration = process.hrtime()
  request
    url: url
    gzip: true
  .then (raw) ->
    duration = process.hrtime(duration)
    duration = duration[0] + (duration[1] / 1e9)
    log.as.info("[http] fetched #{raw.length} bytes in #{duration} seconds (#{(raw.length / duration / 1000).toFixed(2)} KBps)")
    resolve(JSON.parse(raw))
    log.as.debug('[follow] marking change as processed')
    touch.sync("#{__dirname}/../cache/#{changeId}") if changeId?
  .catch (err) ->
    log.as.error(err)
    followed.reject(err)

  followed.promise

module.exports = ->
  findStart().then(follow)
