'use strict'

pipeline = require './pipeline'

pipeline.first()
  .then(pipeline.next)
