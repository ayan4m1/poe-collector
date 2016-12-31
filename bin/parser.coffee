'use strict'

Q = require 'q'
moment = require 'moment'
process = require 'process'

elastic = require './elastic'
timing = require './timing'
log = require './logging'

parseItem = (item) ->
  result = {
    id: item.id
    league: item.league
    x: item.x
    y: item.y
    width: item.w ? 0
    height: item.h ? 0
    name: item.name
    baseLine: null
    rarity: null
    typeLine: item.typeLine
    icon: item.icon
    note: item.note
    level: item.ilvl
    locked: item.lockedToCharacter
    identified: item.identified
    corrupted: item.corrupted
    verified: item.verified
    frame: item.frameType
    frameType: null
    requirements: []
    attributes: []
    modifiers: []
    sockets: []
    stack:
      count: 0
      maximum: null
    price: null
    removed: false
    chaosPrice: 0
    firstSeen: moment().toDate()
  }

  if item.requirements?
    for req in item.requirements
      result.requirements.push
        name: req.name
        value: parseInt(req.values[0][0])
        hidden: req.displayMode is 0

  if item.explicitMods?
    for mod in item.explicitMods
      result.modifiers.push mod

  stackInfo = []
  if item.properties?
    for prop in item.properties
      if prop.name is 'Stack Size' and prop.values?.length > 0
        stackInfo = prop.values[0][0].split(/\//)

      result.attributes.push
        name: prop.name
        values: parseInt(prop.values[0][0]) if prop.values?.length > 0
        hidden: prop.displayMode is 0
        typeId: prop.type

  if item.sockets?
    sockets = {
      red: 0
      green: 0
      blue: 0
      white: 0
      links: []
    }

    # logic for restructuring the socket/link count data
    group = 0
    linkCount = 0
    for socket in item.sockets
      # codes based on stat names Str Dex Int ... Global???
      switch (socket.attr)
        when 'S' then sockets.red++
        when 'D' then sockets.green++
        when 'I' then sockets.blue++
        when 'G' then sockets.white++

      if socket.group is group and linkCount isnt 6
      then linkCount++
      else if linkCount > 1
        sockets.links.push (i for i in [(group + 1) .. linkCount * (group + 1)])
        linkCount = 1

    result.sockets = sockets

  result.price =
    if item.note? then item.note.match(/\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/)
    else if item.stashName? then item.stashName.match(/\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/)

  result.stack =
    count: stackInfo[0]
    maximum: stackInfo[1]

  result

bulk = (type, docs) ->
  bulked = Q.defer()

  elastic.client.bulk({
    index: elastic.config.dataShard
    type: type
    body: docs
  }, (err, res) ->
      return bulked.reject(err) if err?
      bulked.resolve(res) if res?
  )

  bulked.promise

findOrphans = (stashId, itemIds) ->
  found = Q.defer()

  elastic.client.updateByQuery(
    index: elastic.config.dataShard
    type: 'listing'
    body:
      script:
        lang: 'painless'
        inline: 'ctx.removed=true'
      query:
        bool:
          must: [
            parent_id:
              type: 'listing'
              id: stashId
          ]
          must_not: itemIds
  , (err, res) ->
      return found.reject(err) if err?
      found.resolve(res) if res?
  )

  found.promise

update = (item) ->
  added = Q.defer()

  elastic.client.get({
    index: elastic.config.dataShard,
    type: 'listing'
    id: item.id
    parent: item.stash.id
  }, (err, doc) ->
    result = [
      index:
        _index: elastic.config.dataShard
        _type: 'listing'
        _id: item.id
        _parent: item.stash.id
    ]

    if err?.status is 404
      result.push(parseItem(item))
    else if doc?
      doc._source.lastSeen = moment().toDate()
      result.push(doc._source)

    added.resolve(result)
  )

  added.promise

module.exports =
  # merge process
  #   loop through stashes
  #     add stash to bulk list
  #     loop through items in stash
  #       check elastic index for item
  #       parse item if not indexed yet
  #       update price and time if item is indexed
  #       add item to orphan list
  #       check elastic index for orphans
  #       update state for orphans
  merge: (result) ->
    tasks = []
    stashes = []
    listings = []
    timestamp = moment().toDate()

    for stashTab in result.data
      itemsInTab = []
      stash =
        id: stashTab.id
        name: stashTab.stash
        lastSeen: timestamp
        owner:
          account: stashTab.accountName
          character: stashTab.lastCharacterName

      stashes.push({ index: _id: stash.id })
      stashes.push(stash)

      for item in stashTab.items
        item.stash = stash
        listings.push(update(item))
        itemsInTab.push({ term: id: item.id })

      tasks.push(findOrphans(stash.id, itemsInTab))

    bulk('stash', stashes)
      .then (res) ->
        log.as.info("[stash] completed update of #{res.items?.length} stashes")
      .catch(log.as.error)
      .done()

    Q.all(listings)
      .then (items) ->
        result = []
        result.push(item[0], item[1]) for item in items
        bulk('listing', result)
          .then ->
            log.as.info("[listing] completed update of #{items.length} items")
        .catch(log.as.error)
        .done()
      .done()
        # calculate some rate statistics
        #duration = prepareTime.asSeconds()
        #log.as.info("[parser] #{res.affected} items in #{duration.toFixed(2)} seconds (#{Math.floor(items / duration)} items/sec)")

    Q.all(tasks)
      .done ->
        log.as.info('[listing] orphaned listings were marked')

    return
