config = require('konfig')()

Q = require 'q'
moment = require 'moment'
process = require 'process'
jsonfile = require 'jsonfile'

log = require './logging'
parser = require './parser'

buffer =
  docs: []
  count: 0


elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
  requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
)

putTemplate = (name, settings, mappings) ->
  client.indices.putTemplate
    create: false
    name: "#{name}*"
    body:
      template: "#{name}*"
      settings: settings
      mappings: mappings

createTemplates = ->
  schema = jsonfile.readFileSync("#{__dirname}/../schema.json")

  templates = []
  tasks = []
  for shard, info of schema
    shardName = "poe-#{shard}"
    templates.push(putTemplate(shardName, info.settings, info.mappings))

    # only create date partitioned indices for stash and listing
    if shard isnt 'listing' and shard isnt 'stash'
      tasks.push(createIndex(shardName))
    else
      tasks.push(createDatedIndices(shardName, 7))

  Q.allSettled(templates)
    .then(Q.allSettled(tasks))

createIndex = (name) ->
  client.indices.exists({index: name})
    .then (exists) ->
      return if exists
      log.as.info("creating index #{name}")
      client.indices.create({index: name})

createDatedIndices = (baseName, dayCount) ->
  tasks = []
  for day in [ -1 ... dayCount ]
    tasks.push(createIndex("#{baseName}-#{moment().add(day, 'day').format('YYYY-MM-DD')}"))
  Q.all(tasks)

pruneIndices = (baseName, retention) ->
  client.cat.indices(
    index: "poe-#{baseName}*"
    format: 'json'
    bytes: 'm'
  )
    .then (indices) ->
      toRemove = []
      oldestToRetain = moment().subtract(retention.interval, retention.unit)
      for info in indices
        date = moment(info.index.substr(-10), 'YYYY-MM-DD')
        if date.isBefore(oldestToRetain)
          toRemove.push(info.index)
          log.as.info("removing #{info.index} with size #{info['store.size']} MB")
        else
          log.as.info("keeping #{info.index} with size #{info['store.size']} MB")

      return unless toRemove.length > 0
      client.indices.delete({ index: toRemove })
        .then ->
          log.as.info("finished pruning #{toRemove.length} old indices")

getShard = (type, date) ->
  date = date ? moment()
  "poe-#{type}-#{date.format('YYYY-MM-DD')}"

mergeListing = (shard, item) ->
  client.get({
    index: 'poe-listing*'
    type: 'listing'
    id: item.id
  }, (err, res) ->
    return err if err? and err?.status isnt 404

    listing = null
    if err?.status is 404
      listing = parser.listing(item)
    else if res?._source?
      listing = res._source
      listing.lastSeen = moment().toDate()

    if res?._index? and res._index isnt shard
      log.as.info("pulling #{item.id} from #{res._index} into #{shard}")
      # need to remove this document from the old index
      client.delete(
        index: res._index
        type: 'listing'
        id: item.id
      )

    buffer.docs.push({
      index:
        _index: shard
        _type: 'listing'
        _id: item.id
    }, listing)
  )

orphan = (stashId, itemIds) ->
  client.updateByQuery(
    index: 'poe-listing*'
    type: 'listing'
    body:
      script:
        lang: 'painless'
        inline: 'ctx._source.removed=true;ctx._source.lastSeen=ctx._now;'
      query:
        bool:
          must: [{
            term:
              stash: stashId
          }, {
            term:
              removed: false
          }]
          must_not: itemIds
  ).then -> []

mergeStashes = (stashes) ->
  tasks = []
  shard = getShard('stash')
  listingShard = getShard('listing')
  for stash in stashes
    buffer.docs.push({
      index:
        _index: shard
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

    itemIds = []
    for item in stash.items
      item.stash = item.stash ? stash.id

      mergeListing(listingShard, item)

      # build a search term for this item ID so that we can orphan removed items later
      itemIds.push({
        term:
          id: item.id
      })

    tasks.push(orphan(stash.id, itemIds))

  if buffer.docs.length >= config.elastic.batchSize
    buffer.count = buffer.docs.length
    toFlush = buffer.docs
    delete buffer['docs']
    buffer.docs = []
    client.bulk({ body: toFlush })
      .then -> buffer.count = 0

  Q.all(tasks)
    .then -> buffer.count

module.exports =
  updateIndices: ->
    createTemplates()
  pruneIndices: ->
    for type in [ 'stash', 'listing' ]
      pruneIndices(type, config.watcher.retention[type])
  mergeStashes: mergeStashes
  client: client
  config: config.elastic

