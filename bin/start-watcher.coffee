'use strict'
config = require('konfig')()

Primus = require 'primus'
delayed = require 'delayed'
jsonfile = require 'jsonfile'
follow = require './follower'

notifier = Primus.createServer
  port: config.web.socket
  transformer: 'faye'

notifier.on 'connection', (spark) ->
  console.log "new connection from #{spark.address}"

processListing = (result) ->
  console.log "fetched #{result.data.length} stashes"
  for stashTab in result.data
    for item in stashTab.items
      # frameType 5 is currency
      break unless item.frameType is 5
      console.log 'found currency'

      id = item.id
      name = item.typeLine
      # stole these regexes from
      # https://github.com/trackpete/exiletools-indexer/blob/master/subs/sub.formatJSON.pl
      # thanks pete :)
      price =
        if item.note? then item.note.match /\~(b\/o|price|c\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/
        else if item.stashName? then item.stashName.match /\~(b\/o|price|c\/o|gb\/o)\s*((?:\d+)*(?:(?:\.|,)\d+)?)\s*([A-Za-z]+)\s*.*$/

      break unless name? and id? and price?.length > 0
      console.log "adding listing #{id}"
      jsonfile.writeFileSync("#{__dirname}/../cache/listings/#{id}", item)
      notifier.write
        id: id
        name: name
        price: price

# handle is a variable so it can be called recursively
handle = (result) ->
  # todo: wait for new data here
  return unless result.data?

  # process the data
  processListing(result)

  # fetch the next change set to continue
  delayed.delay(->
    result.nextChange()
    .then handle
    .catch (err) ->
      console.error err
    .done()
  , config.watcher.delay * 1000) if result.nextChange?

# main app loop
follow()
.then(handle)
.catch (err) -> console.error err
.done()