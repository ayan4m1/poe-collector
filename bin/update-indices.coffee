'use strict'

elastic = require './elastic'
log = require './logging'

elastic.updateIndices()
  .then -> log.as.info("finished updating elastic indices")
  .catch(log.as.error)
