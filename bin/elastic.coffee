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

  client.get({
    index: config.elastic.dataShard
    type: 'listing'
    id: listing.id
    parent: listing.stash.id
  })
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
          must: [{
            parent_id:
              type: 'listing'
              id: stashId
          }, { term: removed: false }]
          must_not: itemIds
  )

module.exports =
  mergeStashes: (stashes) ->
    merged = Q.defer()

    docs = []
    listings = {}

    for stash in stashes
      docs.push
        index:
          _index: config.elastic.dataShard
          _type: 'stash'
          _id: stash.id
      docs.push(parser.stash(stash))
      listings[stash.id] = stash.items

    duration = process.hrtime()
    client.bulk({ body: docs })
      .then ->
        duration = process.hrtime(duration)
        duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds').asMilliseconds()
        docCount = docs.length / 2
        log.as.info("updated #{docCount} stashes in #{duration}ms (#{Math.floor(docCount / (duration / 1e3))} stashes/sec)")
        merged.resolve(listings)
      .catch(merged.reject)

    merged.promise

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

    duration = process.hrtime()
    Q.allSettled(prepares)
      .then (results) ->
        docs = []

        for result in results
          continue unless result.state is 'fulfilled'
          docs = docs.concat(result.value)

        docCount = docs.length / 2
        tasks.push(client.bulk({body: docs }))
      .then -> Q.all(tasks)
      .then ->
        duration = process.hrtime(duration)
        duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds').asMilliseconds()
        log.as.info("updated #{docCount} listings in #{duration.toFixed(2)}ms (#{Math.floor(docCount / (duration / 1e3))} items/sec)")
      .catch(log.as.error)

  client: client
  config: config.elastic

