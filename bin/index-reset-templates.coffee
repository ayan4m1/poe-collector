'use strict'

elastic = require './elastic'
log = require './logging'

templates = [
  'listing'
]

elastic.dropTemplates(templates)
  .then -> elastic.createTemplates(templates)
  .then -> log.as.info("dropped and re-created templates")
  .catch(log.as.error)
