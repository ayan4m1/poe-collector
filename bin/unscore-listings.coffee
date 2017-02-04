config = require('konfig')()

jsonfile = require 'jsonfile'

log = require './logging'
elastic = require './elastic'

unscoreHit = (hit) ->
  elastic.client.update(
    index: hit._index
    type: 'listing'
    id: hit._id
    body:
      script: 'ctx._source.meta.remove(\"modQuality\")'
  , (err, res) ->
    return log.as.error(err) if err?
    commitCount++ if res.result is 'updated'
  )

hitCount = 0
commitCount = 0

handleSearch = (err, res) ->
  return log.as.error(err) if err?

  unscoreHit(hit) for hit in res.hits.hits
  hitCount += res.hits.hits.length
  return log.as.info("completed!") unless hitCount < res.hits.total
  log.as.info("#{((hitCount / res.hits.total) * 100).toFixed(2)}% complete, #{((commitCount / res.hits.total) * 100).toFixed(2)}% committed (#{commitCount} / #{hitCount} of #{res.hits.total})")
  elastic.client.scroll({
    scroll: '30s'
    scrollId: res._scroll_id
  }, handleSearch)

elastic.client.search({
  index: 'poe-listing*'
  type: 'listing'
  scroll: '30s'
  size: 100
  body: config.query.unscoring
}, handleSearch)
