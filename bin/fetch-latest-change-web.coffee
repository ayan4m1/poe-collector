'use strict'

pipeline = require './pipeline'

pipeline.latest()
  .then (changeId) -> console.log("created #{changeId}")
  .catch(console.error)
