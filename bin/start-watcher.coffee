'use strict'
config = require('konfig')()

fs = require 'fs'
proc = require 'process'
moment = require 'moment'
Primus = require 'primus'
delayed = require 'delayed'
jsonfile = require 'jsonfile'

follow = require './follower'
parser = require './parser'

elasticsearch = require 'elasticsearch'
client = new elasticsearch.Client(
  host: 'http://localhost:9200'
  log: 'error'
  requestTimeout: 180000
)

cacheDir = "#{__dirname}/../cache"

process = (result) ->
  #shard = 'poe-data-' + moment().format('YYYY-MM-DD')
  shard = 'poe-data'
  docs = []
  startTime = proc.hrtime()

  for stashTab in result.data
    for item in stashTab.items
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

      item.price =
        if item.note? then item.note.match /\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/
        else if item.stashName? then item.stashName.match /\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/

      item.stack =
        count: stackInfo
        maximum: stackSize

      # todo: use bulk() with a tuned buffer size
      docs.push(
        index:
          _index: shard
          _type: 'poe-listing'
      )
      docs.push(parsed)

  client.bulk(
    body: docs
  , (err) ->
    console.error(err) if err?
    duration = proc.hrtime(startTime)
    duration = (duration[0] + (duration[1] / 1e9)).toFixed(4)
    console.log "parsed #{result.data.length} items in #{duration} seconds (#{Math.floor(result.data.length / duration)} items/sec)"
  )

  return null

# handle is a variable so it can be called recursively
handle = (result) ->
  # todo: wait for new data here
  return unless result.data?

  # process the data
  process(result)

  # cull any old cache data
  fs.readdir cacheDir, (err, files) ->
    console.error err if err?
    return unless files?.length > 0
    for file in files
      do (file) ->
        fs.stat "#{cacheDir}/#{file}", (err, info) ->
          console.error err if err?
          retainAfter = moment().subtract(config.watcher.retention.interval, config.watcher.retention.unit)
          return unless info.isFile() and moment(info.mtime).isBefore(retainAfter)
          fs.unlinkSync "#{cacheDir}/#{file}"

  # fetch the next change set to continue
  delayMs = moment.duration(config.watcher.delay.interval, config.watcher.delay.unit).asMilliseconds()
  delayed.delay(->
    result.nextChange()
    .then handle
    .catch (err) -> console.error err
    .done()
  , delayMs) if result.nextChange?

###notifier = Primus.createServer
  port: config.web.socket
  transformer: 'faye'

notifier.on 'connection', (spark) ->
  console.log "new connection from #{spark.address}"###

# main app loop
follow()
.then handle
.catch (err) -> console.error err
.done()
