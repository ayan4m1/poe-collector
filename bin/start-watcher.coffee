'use strict'
config = require('konfig')()

Q = require 'q'
fs = require 'fs'
moment = require 'moment'
delayed = require 'delayed'

follow = require './follower'
parser = require './parser'
log = require './logging'

# handle is a variable so it can be called recursively
handle = (result) ->
  parser.merge(result) if result.data?

  # fetch the next change set to continue
  delayMs = moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds()
  delayed.delay(->
    result.nextChange()
    .then(handle)
    .catch(log.as.error)
    .done()
  , delayMs)

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
