config = require('konfig')()

Q = require 'q'
moment = require 'moment'
process = require 'process'
jsonfile = require 'jsonfile'

log = require './logging'
parser = require './parser'

buffer =
  queries: []
  orphans: []

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: config.elastic.host
  log: config.elastic.logLevel
  requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
)

putTemplate = (name, settings, mappings) ->
  log.as.debug("asked to create template #{name}")
  client.indices.putTemplate(
    create: false
    name: "#{name}*"
    body:
      template: "#{name}*"
      settings: settings
      mappings: mappings
  ).catch(log.as.error)

createIndex = (name) ->
  client.indices.exists({index: name})
    .then (exists) ->
      return if exists
      log.as.info("creating index #{name}")
      client.indices.create({index: name})

createDatedIndices = (baseName, dayCount) ->
  tasks = createIndex("#{baseName}-#{moment().add(day, 'day').format('YYYY-MM-DD')}") for day in [ -1 ... dayCount ]
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

      return Q(toRemove) unless toRemove.length > 0
      client.indices.delete({ index: toRemove })
        .then ->
          log.as.info("finished pruning #{toRemove.length} old indices")

getShard = (type, date) ->
  date = date ? moment()
  "poe-#{type}-#{date.format('YYYY-MM-DD')}"

mergeListing = (shard, item) ->
  merged = Q.defer()

  client.search({
    index: 'poe-listing*'
    type: 'listing'
    body:
      query:
        term:
          _id: item.id
  }, (err, res) ->
    return merged.reject(err) if err? and err?.status isnt 404

    listing = null
    verb = 'index'
    if res.hits?.hits?.length is 0 or err?.status is 404
      listing = parser.new(item)
    else if res.hits?.hits?.length is 1
      verb = 'update'
      raw = res.hits.hits[0]
      if raw._index isnt shard
        log.as.silly("moving #{raw._id} up from #{raw._index}")
        buffer.queries.push(client.delete(
          index: raw._index
          type: 'listing'
          id: raw._id
        ))
      listing = raw._source
      parser.existing(item, listing)

    header = {}
    header[verb] =
      _index: shard
      _type: 'listing'
      _id: item.id
    payload = listing
    if verb is 'update'
      payload = { doc: payload }
    merged.resolve([header, payload])
  )

  merged.promise

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
  )

mergeStashes = (stashes) ->
  shard = getShard('stash')
  listingShard = getShard('listing')
  for stash in stashes
    buffer.queries.push(Q([{
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
    }]))

    itemIds = []
    for item in stash.items
      item.stash = item.stash ? stash.id

      buffer.queries.push(mergeListing(listingShard, item))

      # build a search term for this item ID so that we can orphan removed items later
      itemIds.push({
        term:
          id: item.id
      })

    buffer.orphans.push(orphan(stash.id, itemIds))

  return Q() unless buffer.queries.length > config.elastic.batchSize
  log.as.info("flushing batch of #{buffer.queries.length} elastic queries")
  queries = buffer.queries
  buffer.queries = []
  Q.allSettled(queries)
    .then (results) ->
      bulk = []

      for result in results
        if result.state is 'rejected'
          log.as.error(result.reason)
          continue
        Array.prototype.push.apply(bulk, result.value)

      docCount = bulk.length / 2
      log.as.debug("starting bulk of #{docCount} documents")
      duration = process.hrtime()

      client.bulk({ body: bulk })
        .then ->
          duration = process.hrtime(duration)
          bulkTime = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')

          log.as.info("merged #{bulk.length / 2} documents @ #{Math.floor(docCount / bulkTime.asSeconds())} docs/sec")

          orphans = buffer.orphans
          buffer.orphans = []
          Q.allSettled(orphans)
            .then (results) ->
              duration = process.hrtime(duration)
              orphanTime = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')

              orphanCount = 0
              for result in results
                continue unless result.state is 'fulfilled'
                orphanCount += result.value.updated

              log.as.info("orphaned #{orphanCount} documents in #{orphanTime.asMilliseconds()}ms @ #{Math.floor(orphanCount / orphanTime.asSeconds())} docs/sec")
        .catch(log.as.error)

logFetch = (changeId, doc) ->
  buffer.queries.push({
    index:
      _index: 'poe-stats'
      _type: 'fetch'
      _id: changeId
  }, doc)

module.exports =
  updateIndices: ->
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
      .then -> Q.allSettled(tasks)
  pruneIndices: ->
    tasks = []
    for type in [ 'stash', 'listing' ]
      tasks.push(pruneIndices(type, config.watcher.retention[type]))
    Q.all(tasks)
  logFetch: logFetch
  mergeStashes: mergeStashes
  config: config.elastic
