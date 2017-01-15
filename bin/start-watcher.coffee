'use strict'

pipeline = require './pipeline'

handle = ->
  pipeline.next()
    .then(handle)

handle()
  .then(handle)
