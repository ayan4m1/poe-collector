config = require('konfig')()

Q = require 'q'
cheerio = require 'cheerio'
jsonfile = require 'jsonfile'
cloudscraper = require 'cloudscraper'

log = require './logging'

result = {}
promises = []

fetch = (league) ->
  fetched = Q.defer()
  log.as.info("fetching currency offers for league #{league}")
  cloudscraper.get("http://currency.poe.trade/search?league=#{league}&online=x&want=&have=4", (err, res, body) ->
    return fetched.reject(err) if err?

    names = {}
    offers = {}
    results = []
    $ = cheerio.load(body)

    $('#currency-want').find('.currency-selectable').each ->
      $v = $(@)
      return unless $v.children('.currencyimg')?
      id = parseInt($v.data('id'))
      names[id] = $v.attr('title')

    $('div.displayoffer').each ->
      $v = $(@)
      currency = parseInt($v.data('sellcurrency'))
      sell = parseFloat($v.data('sellvalue'))
      buy = parseFloat($v.data('buyvalue'))
      rate = buy / sell

      offers[currency] = [] unless offers[currency]?
      offers[currency].push(rate)

    for currency, val of offers
      continue unless names[currency]?
      continue if names[currency] is 'Chaos Orb'
      total = val.reduce((accum, rate) ->
        accum += rate
      , 0)
      total /= val.length
      total = total.toFixed(2)
      log.as.info("#{names[currency]} averages #{total} chaos")

      results.push {
        name: names[currency]
        value: parseFloat(total)
      }

    results.push { name: 'Chaos Orb', value: 1 }
    result[league] = results
    fetched.resolve()
  )
  fetched.promise

for league in config.static.leagues
  promises.push(fetch(league))

Q.all(promises).then ->
  jsonfile.writeFile("#{__dirname}/../data/ChaosEquivalencies.json", result)
