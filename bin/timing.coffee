Q = require 'q'
moment = require 'moment'
process = require 'process'

module.exports =
  time: (callback) ->
    unless Q.isPromise(callback)
      console.error("callback is not a Q promise");
    start = process.hrtime()
    callback().done()
    end = process.hrtime(start)
    duration = moment.duration(end[0] + (end[1] / 1e9), 'seconds')
    return duration ? 0
