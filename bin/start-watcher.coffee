'use strict'
config = require('konfig')()

fs = require 'fs'
proc = require 'process'
moment = require 'moment'
Primus = require 'primus'
delayed = require 'delayed'
jsonfile = require 'jsonfile'

follow = require './follower'
parser = require './parser'

cacheDir = "#{__dirname}/../cache"

# handle is a variable so it can be called recursively
handle = (result) ->
  # todo: wait for new data here
  return unless result.data?

  # process the data
  Q.denodeify(jsonfile.readFile)()
  .then(parser.parse)

  # cull any old cache data
  fs.readdir cacheDir, (err, files) ->
    console.error err if err?
    return unless files?.length > 0
    for file in files
      do (file) ->
        fs.stat "#{cacheDir}/#{file}", (err, info) ->
          console.error err if err?
          retainAfter = moment().subtract(config.watcher.retention.interval, config.watcher.retention.unit)
          return unless info.isFile() and moment(info.mtime).isBefore(retainAfter)
          fs.unlinkSync "#{cacheDir}/#{file}"

  # fetch the next change set to continue
  delayMs = moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds()
  delayed.delay(->
    result.nextChange()
    .then(handle)
    .catch (err) -> console.error err
    .done()
  , delayMs) if result.nextChange?

###notifier = Primus.createServer
  port: config.web.socket
  transformer: 'faye'

notifier.on 'connection', (spark) ->
  console.log "new connection from #{spark.address}"###

# main app loop
follow()
.then(handle)
.catch (err) -> console.error err
.done()
