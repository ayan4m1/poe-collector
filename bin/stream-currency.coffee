'use strict'
config = require('konfig')()

follow = require './follower'
Primus = require 'primus'

notifier = Primus.createServer
  port: config.web.socket
  transformer: 'faye'

notifier.on 'connection', (spark) ->
  console.log "new connection from #{spark.address}"

handle = (result) ->
  # todo: wait for new data now
  return unless result.data?
  console.log "fetched #{result.data.length} stashes"

  # todo: process the new data
  # todo: tell the sparks

  result.nextChange()
  .then handle
  .catch (err) ->
    console.error err
  .done() if result.nextChange?

follow()
.then handle
.catch (err) ->
  console.error err
.done()