'use strict'

Q = require 'q'
fs = require 'fs'
jsonfile = require 'jsonfile'
request = require 'request-promise'

log = require './logging'

touch = require 'touch'

findStart = ->
  found = Q.defer()

  cacheDir = "#{__dirname}/../cache"
  fs.readdir cacheDir, (err, items) ->
    found.reject(err) if err?
    found.resolve(null) unless items?.length > 0

    # prune non-files
    items = items.filter (v) ->
      return fs.statSync("#{cacheDir}/#{v}").isFile()

    # most recent first
    items.sort (a, b) ->
      fs.statSync("#{cacheDir}/#{a}").mtime.getTime() - fs.statSync("#{cacheDir}/#{b}").mtime.getTime()

    found.resolve(items.pop())

  found.promise

follow = (changeId) ->
  followed = Q.defer()

  # call this one of two ways based on cache state
  resolve = (data) ->
    followed.reject(data) unless data?
    followed.resolve
      data: data.stashes
      nextChange: ->
        console.log "fetching changes from #{data.next_change_id}"
        follow(data.next_change_id)

  cacheFile = "#{__dirname}/../cache/#{changeId}"
  try
    throw new Error() unless changeId?
    fs.accessSync(cacheFile, fs.F_OK)

    console.log "cache hit"
    jsonfile.readFile cacheFile, (err, data) ->
      followed.reject(err) if err?
      resolve(data) if data?
  catch err
    url = 'http://www.pathofexile.com/api/public-stash-tabs'
    url += "?id=#{changeId}" if changeId?

    console.log "miss, fetching #{url}"
    request
      url: url
      gzip: true
    .then (raw) ->
      log.as.info("[http] ]fetched #{raw.length} bytes in #{duration} seconds (#{(raw.length / duration / 1000).toFixed(4)} Kbps)")
      touch.sync(changeId
      resolve(JSON.parse(raw))
    .catch (err) ->
      log.as.error(err)
      followed.reject(err)

  followed.promise

module.exports = ->
  findStart().then(follow)
