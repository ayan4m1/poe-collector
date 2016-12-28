'use strict'
config = require('konfig')()

fs = require 'fs'
moment = require 'moment'
Primus = require 'primus'
delayed = require 'delayed'
elasticsearch = require 'elasticsearch'

follow = require './follower'
parser = require './parser'
log = require './logging'

client = new elasticsearch.Client(
  host: config.watcher.elastic.host
  level: config.watcher.elastic.logLevel
)

cacheDir = "#{__dirname}/../cache"

# handle is a variable so it can be called recursively
handle = (result) ->
  # todo: wait for new data here
  return unless result.data?

  # process the data
  parser.merge(client, result)

  # cull any old cache data
  fs.readdir cacheDir, (err, files) ->
    return log.as.error(err) if err?
    return unless files?.length > 0
    for file in files
      do (file) ->
        fs.stat "#{cacheDir}/#{file}", (err, info) ->
          log.as.error(err) if err?
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
