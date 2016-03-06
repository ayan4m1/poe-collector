'use strict'
config = require('konfig')()

follow = require './follower'
Primus = require 'primus'

Primus.createServer (spark) ->
  console.log spark
,
  port: config.web.socket
  transformer: 'faye'

handle = (result) ->
  console.log "fetched #{result.data.length} stashes"

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