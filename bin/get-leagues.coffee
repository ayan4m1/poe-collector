request = require 'request-promise'
elastic = require 'elasticsearch'

baseUrl = 'http://api.pathofexile.com/leagues?type=main&compact=1'

client = new elastic.Client(
  host: 'http://localhost:9200'
  log: 'debug'
)

request(baseUrl)
.then((data) ->
  leagues = JSON.parse(data)
  console.dir(leagues)

  for league in leagues
    client.index(
      index: 'poe-league'
      type: 'league'
      body: league
    , (err, resp) ->
      console.error(err) if err?
      console.dir(resp) if resp?
    )

).catch((err) ->
  console.error(err)
).done(() ->
  console.log('completed league update')
)
