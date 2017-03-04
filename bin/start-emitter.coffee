config = require('konfig')()

Q = require 'q'
Primus = require 'primus'
moment = require 'moment'

elastic = require './elastic'
log = require './logging'

hosts = []

notifier = Primus.createServer
  port: config.emitter.port
  transformer: 'faye'

log.as.info("emitter started on port #{config.emitter.port}")

notifier.on 'connection', (spark) ->
  log.as.info("new connection from #{spark.address}")
  hosts.push
    spark: spark
    queries: [{
      query:
        bool:
          must: [
            term:
              league: "Breach"
            filter:
              range:
                lastSeen:
                  gt: moment().subtract(10, 'minutes').toISOString()
                  lt: moment().toISOString()
          ]
    }]
  null

process = ->
  log.as.info('starting processing')

  duration = process.hrtime()
  log.as.info("searching for #{hosts.length} connected clients")
  for host in hosts
    searches = []
    for query in host.queries
      searches.push
        index: elastic.config.dataShard
        type: 'listing'
      searches.push(query)

    elastic.client.msearch
      body: searches
    , (err, res) =>
      return log.as.error(err) if err?
      for doc in res.responses
        if doc.hits?.total > 0
          log.as.info("query for host #{host.spark.address} got a hit")
          console.dir(doc)

  return null

processLoop = ->
  Q(process()).delay(
    moment.duration(config.emitter.delay.interval, config.emitter.delay.unit).asMilliseconds() / 5
  ).then(processLoop)

processLoop().done()
