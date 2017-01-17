'use strict'

Q = require 'q'
Orchestrator = require 'orchestrator'

log = require './logging'
pipeline = require './pipeline'

pipeline.sync()
  .then ->
    log.as.info("finished processing backlog")
    pipeline.startWatching()
    pipeline.next()
  .catch(log.as.error)
