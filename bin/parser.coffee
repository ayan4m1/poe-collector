'use strict'

Q = require 'q'
moment = require 'moment'

elastic = require './elastic'
timing = require './timing'
log = require './logging'

parseItem = (item, stashTab) ->
  parsed = Q.defer()

  result = {
    id: item.id
    seller:
      account: stashTab.accountName
      character: stashTab.lastCharacterName
    stash:
      id: item.inventoryId
      league: item.league
      name: item.stash
      x: item.x
      y: item.y
    width: item.w ? 0
    height: item.h ? 0
    name: item.name
    typeLine: item.typeLine
    icon: item.icon
    note: item.note
    level: item.ilvl
    identified: item.identified
    corrupted: item.corrupted
    verified: item.verified
    frame: item.frameType
    requirements: []
    attributes: []
    modifiers: []
    sockets: []
    stack:
      count: 0
      maximum: null
    price: null
    locked: item.lockedToCharacter
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
      linkCount: linkCount
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
        sockets.links.push (i for i in [1 .. linkCount])

    result.sockets = sockets

  result.price =
    if item.note? then item.note.match(/\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/)
    else if item.stashName? then item.stashName.match(/\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/)

  result.stack =
    count: stackInfo[0]
    maximum: stackInfo[1]

  elastic.client.get(
    index: elastic.config.dataShard,
    type: 'poe-listing'
    id: item.id
  , (err, existingDoc) ->
    stamp = moment().toDate()
    result.firstSeen = existingDoc.firstSeen if not err?
    result.firstSeen = stamp if err?
    result.lastSeen = stamp

    parsed.resolve result
  )

  parsed.promise

module.exports =
  merge: (result) ->
    parses = []

    prepareTime = timing.time =>
      for stashTab in result.data
        for item in stashTab.items
          parses.push(parseItem(item, stashTab))

      Q.all(parses)
      .then (results) ->
        docs = []

        for result in results
          docs.push
            index:
              _index: elastic.config.dataShard
              _type: 'poe-listing'
              _id: result.id
          docs.push result

        elastic.client.bulk { body: docs }
      .done()

      return

    # calculate some rate statistics
    items = parses.length
    duration = prepareTime.asSeconds()
    log.as.info("[parser] #{items} items in #{duration.toFixed(2)} seconds (#{Math.floor(items / duration)} items/sec)")
