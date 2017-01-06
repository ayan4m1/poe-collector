'use strict'

pipeline = require './pipeline'

processLoop = ->
  pipeline.next()
    .then(processLoop)


processLoop()
.done()
