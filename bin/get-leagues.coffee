config = require('konfig')()
request = require 'request-promise-native'
elastic = require 'elasticsearch'

log = require './logging'

# this gets us current leagues in a more compact form
baseUrl = 'http://api.pathofexile.com/leagues?type=main&compact=1'

client = new elastic.Client(
  host: config.watcher.elastic.hostname
  log: config.watcher.elastic.logLevel
)

request(baseUrl)
.then((data) ->
  leagues = JSON.parse(data)
  log.as.info("[league] parsed #{leagues.count}")

  for league in leagues
    log.as.debug("[league] processing update for #{league.id}")
    client.index(
      index: config.watcher.elastic.leagueShard
      type: 'league'
      body: league
    , (err, resp) ->
      log.as.error(err) if err?
      log.as.debug(resp) if resp?
    )
).catch(log.as.error)
.done(() ->
  log.as.info('[league] completed league update')
)
