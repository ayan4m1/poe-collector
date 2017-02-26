'use strict'

log = require './logging'
pipeline = require './pipeline'

pipeline.latest()
  .then (changeId) -> log.as.info("created #{changeId}")
  .catch(log.as.error)
