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

mergeListing = (docs, item) ->
  docs.push({
    index:
      _index: config.elastic.dataShard
      _type: 'listing'
      _id: item.id
      _parent: item.stash.id
    }
  ,
      parser.listing(item)
  )

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

mergeStash = (docs, stash) ->
  docs.push({
    index:
      _index: config.elastic.dataShard
      _type: 'stash'
      _id: stash.id
  })
  docs.push({
    id: stash.id
    name: stash.stash
    lastSeen: moment().toDate()
    owner:
      account: stash.accountName
      character: stash.lastCharacterName
  })

  log.as.debug("parsing stash #{stash.id}")
  itemIds = []
  for item in stash.items
    # need a non-circular reference to the ID
    item.stash =
      id: stash.id

    mergeListing(docs, item)

    # build a search term for this item ID so that we can orphan removed items later
    itemIds.push(
      term:
        id: item.id
    )

  # if itemIds is empty, remove all items, otherwise orphan the ones NOT present in itemIds
  orphan(stash.id, itemIds)

mergeStashes = (stashes) ->
  docs = []
  tasks = []

  log.as.info("starting merge of #{stashes.length} stashes")
  for stash in stashes
    tasks.push(mergeStash(docs, stash))

  # bulk the documents and then process orphans
  client.bulk({ body: docs })
    .then(Q.allSettled(tasks))
    .catch(log.as.error)
    .then -> docs.length / 2

module.exports =
  mergeStashes: mergeStashes
  client: client
  config: config.elastic

