'use strict'

elastic = require './elastic'
log = require './logging'

elastic.pruneIndices()
  .then -> log.as.info("removed stale indices")
  .catch(log.as.error)
