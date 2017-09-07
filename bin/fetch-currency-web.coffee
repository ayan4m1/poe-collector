config = require('konfig')()

Q = require 'q'
moment = require 'moment'
cheerio = require 'cheerio'
cloudscraper = require 'cloudscraper'
ntile = require 'stats-percentile'

log = require './logging'
elastic = require './elastic'

getMetadata = () ->
  metadata =
    currencies: []
    leagues: []
  fetched = Q.defer()

  cloudscraper.get('http://currency.poe.trade', (err, res, body) ->
    $ = cheerio.load(body)

    $('#currency-have').find('.currency-square').each ->
      $el = $(@)
      return unless $el.data('id') <= 27
      metadata.currencies.push {
        id: $el.data('id')
        title: $el.attr('title')
      }

    $('select[name="league"]').find('option').each ->
      metadata.leagues.push($(@).val())

    fetched.resolve(metadata)
  )

  fetched.promise

fetch = (league, currency) ->
  fetched = Q.defer()
  log.as.info("fetching currency offers for league #{league}")

  cloudscraper.get("http://currency.poe.trade/search?league=#{league}&online=x&want=#{currency.id}&have=4", (err, res, body) ->
    return fetched.reject(err) if err?

    offers = []
    $ = cheerio.load(body)

    $('div.displayoffer').each ->
      $el = $(@)
      sell = parseFloat($el.data('sellvalue'))
      buy = parseFloat($el.data('buyvalue'))
      rate = buy / sell
      offers.push(rate)

    total = ntile(offers, 95) ? 0
    total = total.toFixed(2)

    log.as.info("#{currency.title} averages #{total} chaos")

    elastic.client.index
      index: 'poe-currency'
      type: 'trade'
      id: "#{league}-#{currency.title}-#{moment().valueOf()}"
      body:
        name: currency.title
        league: league
        chaos: parseFloat(total)
        timestamp: moment().toDate()
      , (err) ->
        fetched.reject(err) if err?
        fetched.resolve()
  )

  fetched.promise

getMetadata()
  .then (metadata) ->
    for league in metadata.leagues
      do (league) ->
        for currency in metadata.currencies
          do (currency) ->
            Q.delay(Math.random() * 120000).then -> fetch(league, currency)
