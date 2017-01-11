'use strict'

elastic = require './elastic'
pipeline = require './pipeline'

handle = ->
  pipeline.next()
    .then(handle)

elastic.updateIndices()
  .then(handle)
  .then(handle)
