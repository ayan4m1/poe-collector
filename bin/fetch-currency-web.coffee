cheerio = require 'cheerio'
jsonfile = require 'jsonfile'
cloudscraper = require 'cloudscraper'

log = require './logging'

names = {}
results = []
offers = {}
currentLeague = 'Legacy'

priceQuery = "http://currency.poe.trade/search?league=#{currentLeague}&online=x&want=&have=4"

cloudscraper.get(priceQuery, (err, res, body) ->
  return log.as.error(err) if err?

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
    total = val.reduce((accum, rate) ->
      accum += rate
    , 0)
    total /= val.length
    total = total.toFixed(2)
    log.as.info("#{names[currency]} averages #{total} chaos")

    results.push {
      id: currency
      name: names[currency]
      value: parseFloat(total)
    }

  jsonfile.writeFile("#{__dirname}/../data/ChaosEquivalencies.json", results)
)
