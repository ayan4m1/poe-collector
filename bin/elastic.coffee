config = require('konfig')()

Q = require 'q'
moment = require 'moment'

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
  requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
)

bulk = (opts) ->
  bulked = Q.defer()

  client.bulk(opts, (err, res) ->
    return bulked.reject(err) if err?
    bulked.resolve(res) if res?
  )

  bulked.promise

module.exports =
  bulk: bulk
  client: client
  config: config.elastic
