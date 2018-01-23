'use strict'

config = require('konfig')()

Q = require 'q'
moment = require 'moment'
process = require 'process'
jsonfile = require 'jsonfile'
elasticsearch = require 'elasticsearch'

log = require './logging'
parser = require './parser'

lastBufferCount = 0

createClient = ->
  new elasticsearch.Client(
    host: config.elastic.host
    log: if config.log.level is 'debug' then 'info' else 'error'
    requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
  )

putTemplate = (name, settings, mappings) ->
  log.as.debug("asked to create template #{name}")
  elastic.client.indices.putTemplate(
    create: false
    name: name
    body:
      index_patterns: "#{name}*"
      settings: settings
      mappings: mappings
  ).catch(log.as.error)

createIndex = (name) ->
  elastic.client.indices.exists({index: name})
    .then (exists) ->
      return if exists
      log.as.info("creating index #{name}")
      elastic.client.indices.create({index: name})

createDatedIndices = (baseName, dayCount) ->
  tasks = createIndex("#{baseName}-#{moment().add(day, 'day').format('YYYY-MM-DD')}") for day in [ -1 ... dayCount ]
  Q.all(tasks)

pruneIndices = (baseName, retention) ->
  elastic.client.cat.indices(
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
      elastic.client.indices.delete({ index: toRemove })
        .then ->
          log.as.info("finished pruning #{toRemove.length} old indices")

updateIndices = ->
  templates = []
  tasks = []
  for shard, info of elastic.schema
    shardName = "poe-#{shard}"
    templates.push(putTemplate(shardName, info.settings, info.mappings))

    # only create date partitioned indices for stash and listing
    if shard isnt 'listing' and shard isnt 'stash'
      tasks.push(createIndex(shardName))
    else
      numDays = moment.duration(config.watcher.retention[shard].interval, config.watcher.retention[shard].unit).asDays()
      tasks.push(createDatedIndices(shardName, numDays))

  Q.allSettled(templates)
    .then -> Q.allSettled(tasks)

pruneAllIndices = ->
  tasks = []
  for type in [ 'stash', 'listing' ]
    tasks.push(pruneIndices(type, config.watcher.retention[type]))
  Q.all(tasks)

getShard = (type, date) ->
  date = date ? moment()
  "poe-#{type}-#{date.format('YYYY-MM-DD')}"

mergeStash = (shard, stash) ->
  elastic.client.search({
    index: 'poe-stash*'
    type: 'stash'
    body:
      query:
        term:
          _id: stash.id
  }, (err, res) ->
    return log.as.error(err) if err? and err?.status isnt 404

    listing = null
    verb = 'index'
    if res.hits?.total is 0 or err?.status is 404
      listing =
        id: stash.id
        name: stash.stash
        lastSeen: moment().toDate()
        owner:
          account: stash.accountName
          character: stash.lastCharacterName
    else if res.hits?.total >= 1
      verb = 'update'
      listing = res.hits.hits[0]._source
      listing.name = stash.stash
      listing.lastSeen = moment().toDate()
      listing.owner.character = stash.lastCharacterName
      if res.hits.total > 1
        oldStashes = 0
        for hitSet in res.hits.hits
          continue unless hitSet._index isnt shard
          oldStashes++
          buffer.orphans.push(elastic.client.delete(
            index: hitSet._index
            type: 'stash'
            id: stash.id
          ))
        log.as.debug("culled #{oldStashes} old copies of stash #{hitSet._id}")

    header = {}
    header[verb] =
      _index: shard
      _type: 'stash'
      _id: stash.id
    payload = listing
    if verb is 'update'
      payload = { doc: payload }
    buffer.stashes.push(header, payload)
  )

appendPayload = (verb, shard, listing) ->
  header = {}
  header[verb] =
    _index: shard
    _type: 'listing'
    _id: listing.id
  payload = listing
  if verb is 'update'
    payload = { doc: payload }

  buffer.listings.push(header, payload)

mergeListings = (shard, items) ->
  merged = Q.defer()
  ids = Object.keys(items)
  elastic.client.search({
    index: 'poe-listing*'
    type: 'listing'
    size: ids.length
    body:
      query:
        ids:
          values: ids
  }, (err, res) ->
    return merged.reject(err) if err? and err?.status isnt 404

    if res.hits?.total > 0
      log.as.silly("#{ids.length} item listings queried, #{res.hits.hits.length} returned")
      for hit in res.hits.hits
        listing = hit._source
        if hit._index isnt shard
          log.as.silly("moving #{hit._id} up from #{hit._index}")
          buffer.orphans.push(elastic.client.delete(
            index: hit._index
            type: 'listing'
            id: hit._id
          ))
        else
          parser.existing(hit, listing)
          appendPayload('update', shard, listing)

    for id, val of items
      appendPayload('index', shard, parser.new(val))

    merged.resolve()
  )

  merged.promise

mergeStashes = (stashes) ->
  merged = Q.defer()
  shard = getShard('stash')
  listingShard = getShard('listing')

  for stash in stashes
    # skip currency tabs
    continue unless stash.stashType is 'PremiumStash'
    items = {}
    ids = []

    mergeStash(shard, stash)
    for item in stash.items
      # associate the item in a hash with id keys
      item.stash = item.stash ? stash.id
      items[item.id] = item

      # build a search term for this item ID so that we can orphan removed items later
      ids.push({
        term:
          id: item.id
      })

    buffer.orphans.push(orphanListing(stash.id, ids))
    # search and upsert all items in this tab
    # todo: convert to flushed buffer
    mergeListings(listingShard, items)
      .catch(merged.reject)
      .then ->
        docCount = buffer.listings.length / 2
        fill = docCount / config.elastic.batchSize
        if fill > lastBufferCount + 0.1 and docCount <= config.elastic.batchSize
          log.as.debug("buffer is #{(fill * 100).toFixed(1)}% full")
          lastBufferCount = fill
        return merged.resolve() unless docCount > config.elastic.batchSize

        stashCount = buffer.stashes.length / 2
        log.as.debug("flushing #{docCount} listings across #{stashCount} stashes")

        slicedBuf = buffer.listings.slice()
        slicedOrphans = buffer.orphans.slice()
        Array.prototype.push.apply(slicedBuf, slicedBuf.stashes)
        buffer.listings.length = buffer.stashes.length = buffer.orphans.length = 0
        lastBufferCount = 0

        bulkDocuments(slicedBuf)
          .catch(merged.reject)
          .then -> orphanListings(slicedOrphans)
          .catch(merged.reject)
          .then(merged.resolve)

  merged.promise

bulkDocuments = (bulk) ->
  bulked = Q.defer()

  docCount = bulk.length / 2
  log.as.debug("starting bulk of #{docCount} documents")
  duration = process.hrtime()
  elastic.client.bulk({ body: bulk })
    .then ->
      bulked.resolve()
      duration = process.hrtime(duration)
      bulkTime = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')
      log.as.info("merged #{docCount} documents @ #{Math.floor(docCount / bulkTime.asSeconds())} docs/sec")
    .catch (err) ->
      bulked.reject(err)
      if err.displayName is 'RequestTimeout'
        log.as.warn('re-creating elastic client due to request timeout!')
        elastic.client = createClient()

  bulked.promise

orphanListings = (orphans) ->
  duration = process.hrtime()

  Q.allSettled(orphans)
    .then (results) ->
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds')

      orphanCount = 0
      for result in results
        continue unless result.state is 'fulfilled' and result.value.updated > 0
        orphanCount += result.value.updated

      return unless orphanCount > 0
      log.as.info("orphaned #{orphanCount} documents in #{duration.asMilliseconds().toFixed(2)}ms @ #{Math.floor(orphanCount / duration.asSeconds())} docs/sec")
    .catch(log.as.error)

orphanListing = (stashId, itemIds) ->
  elastic.client.updateByQuery(
    index: 'poe-listing*'
    type: 'listing'
    requestsPerSecond: 1000
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

logFetch = (changeId, sizeKb, timeMs) ->
  elastic.client.index
    index: 'poe-stats'
    type: 'fetch'
    id: changeId
    body:
      timestamp: moment().toDate()
      fileSizeKb: sizeKb
      downloadTimeMs: timeMs

buffer =
  stashes: []
  listings: []
  orphans: []

elastic =
  client: createClient()
  config: config.elastic
  schema: jsonfile.readFileSync("#{__dirname}/../schema.json")
  updateIndices: updateIndices
  pruneIndices: pruneAllIndices
  mergeStashes: mergeStashes
  logFetch: logFetch

module.exports = elastic
