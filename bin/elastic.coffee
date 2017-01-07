config = require('konfig')()

Q = require 'q'
moment = require 'moment'

parser = require './parser'

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
  requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
)

mergeListing = (item) ->
  key =
    _index: config.elastic.dataShard
    _type: 'listing'
    _id: item.id
    _parent: item.stash.id

  client.exists(
    index: config.elastic.dataShard
    type: 'listing'
    id: item.id
    parent: item.stash.id
  )
    .then (exists) ->
      [
        if exists then { update: key } else { index: key },
        if exists then {
          doc:
            # todo: update price here
            lastSeen: moment().toDate()
        } else parser.listing(item)
      ]

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
    .then -> []

mergeStash = (stash) ->
  merged = Q.defer()
  docs = []

  client.exists(
    index: config.elastic.dataShard
    type: 'stash'
    id: stash.id
  )
    .then (exists) ->
      key =
        _index: config.elastic.dataShard
        _type: 'stash'
        _id: stash.id

      docs.push(
        if exists then { update: key } else { index: key },
        if exists then {
          doc:
            name: stash.name
            lastSeen: moment().toDate()
            owner:
              character: stash.lastCharacterName
        } else {
          id: stash.id
          name: stash.stash
          lastSeen: moment().toDate()
          owner:
            account: stash.accountName
            character: stash.lastCharacterName
        }
      )

      tasks = []
      itemIds = []
      for item in stash.items
        # need a non-circular reference to the ID
        item.stash =
          id: stash.id

        # add a promise to merge this listing
        tasks.push(mergeListing(item))

        # build a search term for this item ID so that we can orphan removed items later
        itemIds.push(
          term:
            id: item.id
        )

      # if itemIds is empty, remove all items, otherwise orphan the ones NOT present in itemIds
      tasks.push(orphan(stash.id, itemIds))

      Q.allSettled(tasks)
        .then (results) ->
          for result in results
            continue unless result.state is 'fulfilled' and result.value.length > 0
            Array.prototype.push.apply(docs, result.value)

          merged.resolve(docs)
        .catch(merged.reject)
      .catch(merged.reject)

  merged.promise

mergeStashes = (stashes) ->
  merged = Q.defer()
  tasks = []
  for stash in stashes
    tasks.push(mergeStash(stash))

  Q.allSettled(tasks)
    .then (results) ->
      docs = []
      for result in results
        continue unless result.state is 'fulfilled' and result.value.length > 0
        Array.prototype.push.apply(docs, result.value)

      client.bulk({ body: docs })
        .then(merged.resolve(docs.length / 2))
        .catch(merged.reject)

  merged.promise

module.exports =
  mergeStashes: mergeStashes
  client: client
  config: config.elastic

