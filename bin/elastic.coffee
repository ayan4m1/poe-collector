config = require('konfig')()

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
)

module.exports =
  client: client
  config: config.elastic
