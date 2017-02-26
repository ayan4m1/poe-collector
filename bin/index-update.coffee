'use strict'

elastic = require './elastic'
log = require './logging'

elastic.updateIndices()
  .catch(log.as.error)
  .then -> log.as.info("finished updating elastic indices")
