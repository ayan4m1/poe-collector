config = require('konfig')()

Q = require 'q'
moment = require 'moment'
jsonfile = require 'jsonfile'

log = require './logging'
parser = require './parser'

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

  tasks = []
  for shard, info of schema
    shardName = "poe-#{shard}"
    tasks.push(putTemplate(shardName, info.settings, info.mappings))

    # only create date partitioned indices for stash and listing
    if shard isnt 'listing' and shard isnt 'stash'
      tasks.push(createIndex(shardName))
    else
      tasks.push(createDatedIndices(shardName, 7))

  Q.all(tasks)

createIndex = (name) ->
  client.indices.exists({ index: name })
  .then (exists) ->
    return if exists
    log.as.info("creating index #{name}")
    client.indices.create({ index: name })

createDatedIndices = (baseName, dayCount) ->
  tasks = []
  for day in [ -1 ... dayCount ]
    tasks.push(createIndex("#{baseName}-#{moment().add(day, 'day').format('YYYY-MM-DD')}"))
  Q.all(tasks)

mergeListing = (item) ->
  merged = Q.defer()

  shard = "poe-listing-#{moment().format('YYYY-MM-DD')}"
  client.get({
    index: shard
    type: 'listing'
    id: item.id
  }, (err, res) ->
    return merged.reject(err) if err? and err?.status isnt 404

    listing = if err?.status is 404 then parser.listing(item) else res._source
    listing.lastSeen = moment().toDate() unless err?.status is 404

    shard = "poe-listing-#{moment().format('YYYY-MM-DD')}"
    merged.resolve([{
      index:
        _index: shard
        _type: 'listing'
        _id: item.id
    }, listing])
  )

  merged.promise

orphan = (stashId, itemIds) ->
  shard = "poe-listing-#{moment().format('YYYY-MM-DD')}"
  client.updateByQuery(
    index: shard
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
  )

mergeStash = (stash) ->
  log.as.debug("parsing stash #{stash.id}")
  tasks = []
  itemIds = []
  for item in stash.items
    item.stash = stash.id

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
  shard = "poe-stash-#{moment().format('YYYY-MM-DD')}"
  for stash in stashes
    docs.push({
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

    Array.prototype.push.apply(tasks, mergeStash(stash))

  Q.all(tasks)
    .then (results) ->
      for result in results
        continue unless Array.isArray(result)
        Array.prototype.push.apply(docs, result)

      client.bulk({ body: docs })

      Q(docs.length / 2)

module.exports =
  updateIndices: ->
    createTemplates()
      .then ->
        log.as.info("finished setting up indices")
  mergeStashes: mergeStashes
  client: client
  config: config.elastic

