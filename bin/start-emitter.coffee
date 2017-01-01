config = require('konfig')()

Q = require 'q'
Primus = require 'primus'
delayed = require 'delayed'
moment = require 'moment'

timing = require './timing'
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
    address: spark.address
    queries: [
      query:
        bool:
          must:
            term:
              league: 'Breach'
    ]

process = ->
  log.as.info('starting processing')

  processTime = timing.time ->
    log.as.info("searching for #{hosts.length} connected clients")
    for host in hosts
      searches = []
      for query in host.queries
        searches.push
          index: elastic.config.dataShard
        searches.push(query)

      elastic.client.msearch host.queries
      , (err, res) ->
        return log.as.error(err) if err?
        if res.hits?.hits > 0
          log.as.info("query for host #{host.address} got a hit")
          console.dir(res)

  log.as.info("host queue exhausted in #{processTime.asMilliseconds().toFixed(2)}ms")
  return null

processLoop = ->
  Q(process()).then ->
    delayed.delay(
      processLoop,
      moment.duration(config.emitter.delay.interval, config.emitter.delay.unit).asMilliseconds()
    )

processLoop().done()
