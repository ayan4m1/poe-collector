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

get = Q.denodeify(client.get)
updateByQuery = Q.denodeify(client.updateByQuery)

merge = (listing) ->
  get(
    index: config.dataShard,
    type: 'listing'
    id: item.id
    parent: item.stash.id
  )
  .catch (err) -> parser.listing(listing) if err.status is 404
  .then (item) ->
    result = [
      index:
        _index: elastic.config.dataShard
        _type: 'listing'
        _id: listing.id
        _parent: listing.stash.id
    ]

    item._source.lastSeen = moment().toDate()
    item._source
    result.push(item)

    result

markOrphans = (stashId, itemIds) ->
  updateByQuery(
    index: elastic.config.dataShard
    type: 'listing'
    body:
      script:
        lang: 'painless'
        inline: 'ctx._source.removed=true;ctx._source.lastSeen=ctx._now;'
      query:
        bool:
          must: [
            parent_id:
              type: 'listing'
              id: stashId
          ]
          must_not: itemIds
  ).catch(log.as.error)
    .then (res) ->
      console.dir(res)

module.exports =
  bulk: bulk
  merge: merge
  markOrphans: markOrphans()
  client: client
  config: config.elastic
  shard: config.elastic.dataShard + moment().format('-YYYY-MM-DD')

