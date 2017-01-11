config = require('konfig')()

Q = require 'q'
moment = require 'moment'

log = require './logging'
parser = require './parser'

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
  requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
)

mergeListing = (item) ->
  merged = Q.defer()

  client.get({
    index: config.elastic.dataShard
    type: 'listing'
    id: item.id
    parent: item.stash.id
  }, (err, res) ->
    return merged.reject(err) if err? and err?.status isnt 404

    listing = if err?.status is 404 then parser.listing(item) else res._source
    listing.lastSeen = moment().toDate() if res?

    merged.resolve([{
      index:
        _index: config.elastic.dataShard
        _type: 'listing'
        _id: item.id
        _parent: item.stash.id
    }, listing])
  )

  merged.promise

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

mergeStash = (stash) ->
  log.as.debug("parsing stash #{stash.id}")
  tasks = []
  itemIds = []
  for item in stash.items
    # need a non-circular reference to the ID
    item.stash =
      id: stash.id

    tasks.push(mergeListing(item))

    # build a search term for this item ID so that we can orphan removed items later
    itemIds.push(
      term:
        id: item.id
    )

  tasks.push(orphan(stash.id, itemIds))

  tasks

mergeStashes = (stashes) ->
  docs = []
  tasks = []

  log.as.info("starting merge of #{stashes.length} stashes")
  for stash in stashes
    docs.push({
      index:
        _index: config.elastic.dataShard
        _type: 'stash'
        _id: stash.id
    }, {
      id: stash.id
      name: stash.stash
      lastSeen: moment().toDate()
      owner:
        account: stash.accountName
        character: stash.lastCharacterName
    })

    Array.prototype.push.apply(tasks, mergeStash(stash))

  client.bulk({ body: docs })
    .then -> Q.all(tasks)
    .then (results) ->
      listings = []

      for result in results
        continue unless Array.isArray(result)
        Array.prototype.push.apply(listings, result)

      client.bulk({ body: listings })
        .then -> listings.length / 2


module.exports =
  mergeStashes: mergeStashes
  client: client
  config: config.elastic

