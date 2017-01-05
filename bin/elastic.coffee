config = require('konfig')()

Q = require 'q'
moment = require 'moment'
process = require 'process'

log = require './logging'
parser = require './parser'

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
  requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
)

mergeListing = (listing) ->
  result = [
    index:
      _index: config.elastic.dataShard
      _type: 'listing'
      _id: listing.id
      _parent: listing.stash.id
  ]

  client.get(
    index: config.elastic.dataShard,
    type: 'listing'
    id: listing.id
    parent: listing.stash.id
  )
    .then (item) ->
      item._source.lastSeen = moment().toDate()
      result.push(item._source)
      result
    .catch (err) ->
      result.push(parser.listing(listing)) if err.status is 404
      result

orphan = (stashId, itemIds) ->
  client.updateByQuery(
    index: config.elastic.dataShard
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
          ,
            term:
              removed: false
          ]
          must_not: itemIds
  ).then (results) ->
    return unless results.updated > 0
    log.as.info("orphaned #{results.updated} items from stash #{stashId}")

module.exports =
  mergeStashes: (stashes) ->
      docs = []
      listings = {}

      for stash in stashes
        docs.push
          index:
            _index: 'poe-data'
            _type: 'stash'
            _id: stash.id
        docs.push(parser.stash(stash))
        listings[stash.id] = stash.items

      duration = process.hrtime()
      client.bulk({ body: docs })
        .then ->
          duration = process.hrtime(duration)
          duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds').asMilliseconds()
          log.as.info("updated #{docs.length / 2} stashes in #{duration}ms (#{Math.floor((duration * 1e3) / (docs.length / 2))} stashes/sec)")

      Q(listings)

  mergeListings: (data) ->
    tasks = []
    prepares = []
    docCount = 0

    for stashId, listings of data
      for listing in listings
        listing.stash =
          id: stashId
        prepares.push(mergeListing(listing))

      itemIds = listings.map (listing) ->
        term:
          id: listing.id

      tasks.push(orphan(stashId, itemIds))

    tasks.push(
      Q.allSettled(prepares)
        .then (results) ->
          docs = []

          for result in results
            continue unless result.state is 'fulfilled'
            docs = docs.concat(result.value)

          docCount = docs.length / 2
          client.bulk({ body: docs })
        .catch(log.as.error)
    )

    duration = process.hrtime()
    Q.all(tasks)
      .then ->
        duration = process.hrtime(duration)
        duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds').asMilliseconds()
        log.as.info("updated #{docCount} listings in #{duration.toFixed(2)}ms (#{Math.floor((duration * 1e3) / docCount)} items/sec)")
      .catch(log.as.error)

  client: client
  config: config.elastic

