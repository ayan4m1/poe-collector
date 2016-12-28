Q = require 'q'

config = require('konfig')()

timing = require './timing'
log = require './logging'

parseItem = (item, stashTab) ->
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

parseItems = (result) ->
  docs = []

  for stashTab in result.data
    for item in stashTab.items
      docs.push(
        index:
          _index: config.watcher.elastic.dataShard
          _type: 'poe-listing'
      )
      docs.push(parseItem(item, stashTab))

  docs

module.exports =
  merge: (client, result) ->
    docs = null

    prepareTime = timing.time ->
      docs = parseItems(result)

    updateTime = timing.time ->
      Q.denodeify(client.bulk({ body: docs }))

    items = docs.length / 2
    duration = prepareTime.asSeconds() + updateTime.asSeconds()
    log.as.info("[parser] #{items} items in #{duration.toFixed(2)} seconds (#{Math.floor(items / duration)} items/sec)")
    log.as.info("[parser] prepare #{prepareTime.asSeconds().toFixed(4)}s update #{updateTime.asSeconds().toFixed(2)}s")