'use strict'

config = require('konfig')()

Q = require 'q'
moment = require 'moment'
elasticsearch = require 'elasticsearch'

values = {}

elastic =
  client: new elasticsearch.Client(
    host: config.elastic.host
    log: if config.log.level is 'debug' then 'info' else 'error'
    requestTimeout: moment.duration(config.elastic.timeout.interval, config.elastic.timeout.unit).asMilliseconds()
  )

fetchValue = (league) ->
  fetched = Q.defer()

  elastic.client.search
    index: 'poe-currency'
    body:
      query:
        term:
          league: league
      size: 1000
      sort:
        timestamp:
          order: 'desc'
  , (err, res) ->
    return fetched.reject(err) if err?
    values = {}
    existing = []
    values[league] = {}
    for hit in res.hits.hits
      listing = hit._source
      continue unless existing.indexOf(listing.name) is -1
      if listing.name is 'Chaos Orb'
        values[league]['Chaos Orb'] = 1
        continue
      values[league][listing.name] = listing.chaos
      existing.push listing.name
    fetched.resolve(values)

  fetched.promise

fetchValues = ->
  promises = []

  for league in config.static.leagues
    promises.push fetchValue(league)

  Q.all(promises)
    .then (results) ->
      result = {}
      for value in results
        Object.assign(result, value)
      result

module.exports =
  fetchValues: fetchValues
