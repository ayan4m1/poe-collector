Q = require 'q'
process = require 'process'

elastic = require './elastic'
log = require './logging'

markOrphans = (listings) ->
  tasks = []

  for stashId, listings of listings
    itemIds = listings.map (listing) ->
      term:
        id: listing.id

    tasks.push(elastic.markOrphans(stashId, itemIds))

  Q.all(tasks)
    .then ->
      log.as.info("finished marking orphans")

mergeStashes = (stashes) ->
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
  elastic.bulk(docs)
    .then ->
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds').asMilliseconds()
      log.as.info("stash update completed in #{duration}ms")

      listings

mergeListings = (data) ->
  docs = []

  for stashId, listings of data
    for listing in listings
      docs.push
        index:
          _index: 'poe-data'
          _type: 'listing'
          _id: listing.id
          _parent: stashId
      docs.push(parser.listing(listing))

  duration = process.hrtime()
  elastic.bulk(docs)
    .then ->
      duration = process.hrtime(duration)
      duration = moment.duration(duration[0] + (duration[1] / 1e9), 'seconds').asMilliseconds()
      count = docs.length / 2
      log.as.info("listing update of #{count} completed in #{duration.toFixed(2)}ms (#{count / duration} items/sec")

      data

find = (previous) ->
  return Q(previous) if previous?

  readDir("#{__dirname}/../cache}")
    .then (items) ->
      items = items.filter (v) ->
        fs.statSync("#{base}/#{v}").isFile()
      items.sort (a, b)->
        fs.statSync("#{base}/#{a}").mtime.getTime() - fs.statSync("#{base}/#{b}").mtime.getTime()
      items.pop()

merge = (data) ->
  mergeStashes(data.stashes)
    .then(mergeListings)
    .then(markOrphans)
    .then ->
      merge(data.next_change_id) if data.next_change_id?

module.exports =
  follow: ->
    update().then(follow)
  update: (data) ->
    find().then(merge)
