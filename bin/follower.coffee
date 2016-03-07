'use strict'

Q = require 'q'
fs = require 'fs'
jsonfile = require 'jsonfile'
request = require 'request-promise'

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
      followed.reject err if err?
      resolve(data) if data?
  catch err
    url = 'http://www.pathofexile.com/api/public-stash-tabs'
    url += "?id=#{changeId}" if changeId?

    console.log "miss, fetching #{url}"
    request
      url: url
      gzip: true
    .then (raw) ->
      console.log "fetched #{raw.length} bytes"
      data = JSON.parse(raw)
      jsonfile.writeFile(cacheFile, data)
      resolve(data)
    , (err) ->
      followed.reject(err)

  followed.promise

module.exports = follow