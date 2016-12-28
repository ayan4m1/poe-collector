Q = require 'q'
jsonfile = require 'jsonfile'

timing = require './timing'

parse = (item) ->
  parsed = {
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
  }

  if item.requirements?
    for req in item.requirements
      parsed.requirements.push
        name: req.name
        minimum: req.values.min
        maximum: req.values.max
        hidden: req.displayMode is 0

  if item.explicitMods?
    for mod in item.explicitMods
      parsed.modifiers.push mod

  if item.properties?
    for prop in item.properties
      if prop.name is 'Stack Size' and prop.values?.length > 0
        stackInfo = prop.values[0][0]
        continue unless stackInfo?
        stackSize = stackInfo.split(/\//)[0]

      parsed.attributes.push
        name: prop.name
        minimum: prop.values.min
        maximum: prop.values.max
        hidden: prop.displayMode is 0
        typeId: prop.type

  if item.sockets?
    for socket in item.sockets
      parsed.sockets.push socket

  parsed.price =
    if item.note? then item.note.match /\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/
    else if item.stashName? then item.stashName.match /\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/

  parsed.stack =
    count: stackInfo
    maximum: stackSize

  parsed

module.exports = (path) ->
  parse: ->

    .then (result) ->
      docs = []
      prepareTime = timing.time =>
        for stashTab in result.data
          for item in stashTab.items
            docs.push(
              index:
                _index: shard
                _type: 'poe-listing'
            )
            docs.push(parse(item))

      updateTime = timing.time ->
        client.bulk(
          body: docs
        , (err) ->
          console.error(err) if err?
          duration = proc.hrtime(startTime)
          duration = (duration[0] + (duration[1] / 1e9)).toFixed(4)
          console.log "parsed #{result.data.length} items in #{duration} seconds (#{Math.floor(result.data.length / duration)} items/sec)"
        )

      log.as.info("[profiling] prepare #{prepareTime.toFixed(4)}s update #{updateTime.toFixed(2)}")
      console.log('finished processing')
    .catch log.as.error
    .done()
