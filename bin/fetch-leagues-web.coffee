moment = require 'moment'
requestPromise = require 'request-promise-native'

log = require './logging'
elastic = require './elastic'

requestPromise({
  uri: 'http://api.pathofexile.com/leagues?type=main&compact=1'
})
  .then (data) ->
    leagues = JSON.parse(data)
    return log.as.error("invalid response from server:\r\n\r\n#{data}") unless leagues?
    log.as.info("[league] parsed #{leagues.count} active leagues")

    for league in leagues
      log.as.debug("[league] updating #{league.id}")
      elastic.client.index(
        index: 'poe-league'
        type: 'league'
        body: league
      , (err, resp) ->
        log.as.error(err) if err?
        log.as.warn(resp) if resp.failed > 0
      )
  .catch(log.as.error)
