'use strict'

pipeline = require './pipeline'

handle = ->
  pipeline.next()
    .then(pipeline.next)

handle()
  .then(handle)
